// Food lookups (BE-07): Open Food Facts barcodes and search, plus USDA
// FoodData Central search when a key is set, normalised to one shape and
// cached at the edge for 30 days. OFF data is ODbL: attribution travels with
// every item.

export interface NormalizedFood {
  id: string;
  source: "openfoodfacts" | "usda";
  barcode?: string;
  name: string;
  brand?: string;
  servingSizeG?: number;
  servingLabel?: string;
  per100g: {
    kcal: number;
    proteinG: number;
    carbsG: number;
    fatG: number;
    fiberG?: number;
    sugarG?: number;
    sodiumMg?: number;
  };
  attribution: { source: string; license: string; url: string };
}

export const FOOD_CACHE_SECONDS = 30 * 24 * 3600;
export const NOT_FOUND_CACHE_SECONDS = 24 * 3600;
export const USER_AGENT = "LifeOS/1.0 (ai-proxy; https://github.com/intenzee/LifeOS)";

const OFF_FIELDS = "code,product_name,brands,serving_size,serving_quantity,nutriments";

export interface FoodCache {
  get(key: string): Promise<unknown | undefined>;
  put(key: string, value: unknown, ttlSeconds: number): Promise<void>;
}

export class MemoryFoodCache implements FoodCache {
  readonly entries = new Map<string, unknown>();
  async get(key: string) {
    return this.entries.get(key);
  }
  async put(key: string, value: unknown) {
    this.entries.set(key, value);
  }
}

export function isBarcode(code: string): boolean {
  return /^\d{8,14}$/.test(code);
}

type Nutriments = Record<string, unknown>;

function num(value: unknown): number | undefined {
  const n = typeof value === "string" ? Number(value) : value;
  return typeof n === "number" && Number.isFinite(n) && n >= 0 ? n : undefined;
}

/** An OFF product, or `null` when it has no name or no energy (not worth logging). */
export function normaliseOFF(product: Record<string, unknown>): NormalizedFood | null {
  const code = String(product.code ?? "");
  const name = String(product.product_name ?? "").trim();
  const n = (product.nutriments ?? {}) as Nutriments;
  const kcal = num(n["energy-kcal_100g"]) ?? (num(n["energy_100g"]) !== undefined ? num(n["energy_100g"])! / 4.184 : undefined);
  if (!name || kcal === undefined) return null;
  const sodiumG = num(n["sodium_100g"]) ?? (num(n["salt_100g"]) !== undefined ? num(n["salt_100g"])! / 2.5 : undefined);
  return {
    id: `off:${code}`,
    source: "openfoodfacts",
    barcode: code || undefined,
    name,
    brand: String(product.brands ?? "").split(",")[0]?.trim() || undefined,
    servingSizeG: num(product.serving_quantity),
    servingLabel: typeof product.serving_size === "string" ? product.serving_size : undefined,
    per100g: {
      kcal: round(kcal),
      proteinG: round(num(n["proteins_100g"]) ?? 0),
      carbsG: round(num(n["carbohydrates_100g"]) ?? 0),
      fatG: round(num(n["fat_100g"]) ?? 0),
      fiberG: optionalRound(num(n["fiber_100g"])),
      sugarG: optionalRound(num(n["sugars_100g"])),
      sodiumMg: sodiumG === undefined ? undefined : round(sodiumG * 1000),
    },
    attribution: {
      source: "Open Food Facts",
      license: "ODbL-1.0",
      url: `https://world.openfoodfacts.org/product/${code}`,
    },
  };
}

/** A USDA FoodData Central search hit (per 100 g for Foundation/SR/Branded). */
export function normaliseUSDA(food: Record<string, unknown>): NormalizedFood | null {
  const nutrients = (food.foodNutrients ?? []) as { nutrientNumber?: string; nutrientId?: number; value?: number }[];
  const value = (number: string) => num(nutrients.find((x) => x.nutrientNumber === number)?.value);
  const kcal = value("208") ?? value("957") ?? value("958");
  const name = String(food.description ?? "").trim();
  if (!name || kcal === undefined) return null;
  const id = String(food.fdcId ?? "");
  return {
    id: `usda:${id}`,
    source: "usda",
    barcode: typeof food.gtinUpc === "string" ? food.gtinUpc : undefined,
    name,
    brand: typeof food.brandOwner === "string" ? food.brandOwner : undefined,
    servingSizeG: food.servingSizeUnit === "g" ? num(food.servingSize) : undefined,
    per100g: {
      kcal: round(kcal),
      proteinG: round(value("203") ?? 0),
      carbsG: round(value("205") ?? 0),
      fatG: round(value("204") ?? 0),
      fiberG: optionalRound(value("291")),
      sugarG: optionalRound(value("269")),
      sodiumMg: optionalRound(value("307")),
    },
    attribution: { source: "USDA FoodData Central", license: "CC0-1.0", url: `https://fdc.nal.usda.gov/food-details/${id}` },
  };
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

function optionalRound(value: number | undefined): number | undefined {
  return value === undefined ? undefined : round(value);
}

export interface FoodDeps {
  fetch: typeof fetch;
  cache: FoodCache;
  usdaKey?: string;
}

/** `null` when no product with usable nutrition exists (cached for a day). */
export async function barcode(code: string, deps: FoodDeps): Promise<NormalizedFood | null> {
  const key = `barcode:${code}`;
  const cached = await deps.cache.get(key);
  if (cached !== undefined) return (cached as { food: NormalizedFood | null }).food;

  const response = await deps.fetch(
    `https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=${OFF_FIELDS}`,
    { headers: { "user-agent": USER_AGENT } },
  );
  if (!response.ok && response.status !== 404) throw new Error(`openfoodfacts ${response.status}`);
  const payload = response.ok ? ((await response.json()) as { status?: number; product?: Record<string, unknown> }) : {};
  const food = payload.status === 1 && payload.product ? normaliseOFF({ code, ...payload.product }) : null;
  await deps.cache.put(key, { food }, food ? FOOD_CACHE_SECONDS : NOT_FOUND_CACHE_SECONDS);
  return food;
}

export async function search(query: string, deps: FoodDeps): Promise<NormalizedFood[]> {
  const q = query.trim().toLowerCase().replace(/\s+/g, " ").slice(0, 80);
  if (q.length < 2) return [];
  const key = `search:${q}`;
  const cached = await deps.cache.get(key);
  if (cached !== undefined) return cached as NormalizedFood[];

  const off = deps.fetch(
    `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(q)}&search_simple=1&json=1&page_size=20&fields=${OFF_FIELDS}`,
    { headers: { "user-agent": USER_AGENT } },
  ).then(async (r) => (r.ok ? ((await r.json()) as { products?: Record<string, unknown>[] }).products ?? [] : []))
    .then((products) => products.map(normaliseOFF))
    .catch(() => [] as (NormalizedFood | null)[]);

  const usda = deps.usdaKey
    ? deps.fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${deps.usdaKey}&pageSize=20&query=${encodeURIComponent(q)}`,
      { headers: { "user-agent": USER_AGENT } })
      .then(async (r) => (r.ok ? ((await r.json()) as { foods?: Record<string, unknown>[] }).foods ?? [] : []))
      .then((foods) => foods.map(normaliseUSDA))
      .catch(() => [] as (NormalizedFood | null)[])
    : Promise.resolve([] as (NormalizedFood | null)[]);

  const [fromOFF, fromUSDA] = await Promise.all([off, usda]);
  const results = interleave(fromUSDA.filter(isFood), fromOFF.filter(isFood)).slice(0, 25);
  // Don't pin an outage for 30 days.
  if (results.length > 0) await deps.cache.put(key, results, FOOD_CACHE_SECONDS);
  return results;
}

function isFood(food: NormalizedFood | null): food is NormalizedFood {
  return food !== null;
}

function interleave<T>(a: T[], b: T[]): T[] {
  const out: T[] = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== undefined) out.push(a[i]!);
    if (b[i] !== undefined) out.push(b[i]!);
  }
  return out;
}
