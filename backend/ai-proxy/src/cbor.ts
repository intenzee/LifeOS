// Minimal CBOR (RFC 8949) for App Attest objects: unsigned/negative ints, byte
// and text strings, arrays, maps, booleans and null. Definite lengths only,
// which is all Apple emits. The encoder exists for tests and fixtures.

export type CBORValue =
  | number
  | string
  | boolean
  | null
  | Uint8Array
  | CBORValue[]
  | Map<CBORValue, CBORValue>;

export class CBORError extends Error {}

export function decodeCBOR(bytes: Uint8Array): CBORValue {
  const reader = { bytes, offset: 0 };
  const value = readItem(reader, 0);
  if (reader.offset !== bytes.length) throw new CBORError("trailing bytes");
  return value;
}

interface Reader {
  bytes: Uint8Array;
  offset: number;
}

const MAX_DEPTH = 16;

function readByte(r: Reader): number {
  const b = r.bytes[r.offset];
  if (b === undefined) throw new CBORError("unexpected end");
  r.offset += 1;
  return b;
}

function readLength(r: Reader, info: number): number {
  if (info < 24) return info;
  const size = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
  if (size === 0) throw new CBORError(`unsupported length encoding ${info}`);
  let value = 0;
  for (let i = 0; i < size; i++) value = value * 256 + readByte(r);
  if (!Number.isSafeInteger(value)) throw new CBORError("length too large");
  return value;
}

function take(r: Reader, length: number): Uint8Array {
  if (r.offset + length > r.bytes.length) throw new CBORError("unexpected end");
  const out = r.bytes.slice(r.offset, r.offset + length);
  r.offset += length;
  return out;
}

function readItem(r: Reader, depth: number): CBORValue {
  if (depth > MAX_DEPTH) throw new CBORError("nested too deeply");
  const initial = readByte(r);
  const major = initial >> 5;
  const info = initial & 0x1f;
  switch (major) {
    case 0:
      return readLength(r, info);
    case 1:
      return -1 - readLength(r, info);
    case 2:
      return take(r, readLength(r, info));
    case 3:
      return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(take(r, readLength(r, info)));
    case 4: {
      const length = readLength(r, info);
      const items: CBORValue[] = [];
      for (let i = 0; i < length; i++) items.push(readItem(r, depth + 1));
      return items;
    }
    case 5: {
      const length = readLength(r, info);
      const map = new Map<CBORValue, CBORValue>();
      for (let i = 0; i < length; i++) map.set(readItem(r, depth + 1), readItem(r, depth + 1));
      return map;
    }
    case 6:
      readLength(r, info); // tag number: ignored, the tagged item is returned
      return readItem(r, depth + 1);
    case 7:
      if (info === 20) return false;
      if (info === 21) return true;
      if (info === 22 || info === 23) return null;
      throw new CBORError(`unsupported simple value ${info}`);
    default:
      throw new CBORError(`unsupported major type ${major}`);
  }
}

/** Reads `key` from a CBOR map with text keys. */
export function field(value: CBORValue, key: string): CBORValue | undefined {
  return value instanceof Map ? value.get(key) : undefined;
}

export function bytesField(value: CBORValue, key: string): Uint8Array {
  const v = field(value, key);
  if (!(v instanceof Uint8Array)) throw new CBORError(`missing byte string "${key}"`);
  return v;
}

// MARK: - Encoder (tests and fixtures)

export function encodeCBOR(value: CBORValue): Uint8Array {
  const out: number[] = [];
  write(out, value);
  return new Uint8Array(out);
}

function header(out: number[], major: number, length: number): void {
  if (length < 24) out.push((major << 5) | length);
  else if (length < 0x100) out.push((major << 5) | 24, length);
  else if (length < 0x10000) out.push((major << 5) | 25, length >> 8, length & 0xff);
  else out.push((major << 5) | 26, (length >>> 24) & 0xff, (length >> 16) & 0xff, (length >> 8) & 0xff, length & 0xff);
}

function write(out: number[], value: CBORValue): void {
  if (value === null) out.push(0xf6);
  else if (value === true) out.push(0xf5);
  else if (value === false) out.push(0xf4);
  else if (typeof value === "number") {
    if (!Number.isInteger(value)) throw new CBORError("floats are not supported");
    if (value >= 0) header(out, 0, value);
    else header(out, 1, -1 - value);
  } else if (typeof value === "string") {
    const bytes = new TextEncoder().encode(value);
    header(out, 3, bytes.length);
    out.push(...bytes);
  } else if (value instanceof Uint8Array) {
    header(out, 2, value.length);
    for (const b of value) out.push(b);
  } else if (Array.isArray(value)) {
    header(out, 4, value.length);
    for (const item of value) write(out, item);
  } else {
    header(out, 5, value.size);
    for (const [k, v] of value) {
      write(out, k);
      write(out, v);
    }
  }
}
