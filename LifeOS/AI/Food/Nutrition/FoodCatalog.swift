import Foundation

/// One food in the bundled catalog: nutrition per 100 g (or 100 ml for drinks)
/// plus household measures, so "2 rotis" or "1 katori dal" resolves to grams.
nonisolated struct FoodRecord: Sendable, Hashable, Identifiable {
    nonisolated enum Category: String, Sendable, Hashable, CaseIterable {
        case bread, rice, dal, vegCurry, nonVegCurry, southIndian, snack, sweet, beverage, dairy, egg, fruit,
             vegetable, grain, western, fastFood, fat, nuts, supplement, condiment, packaged
    }

    let id: String
    let name: String
    let aliases: [String]
    let category: Category
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// Grams (or ml) per household unit for *this* food, e.g. ["piece": 40] for roti.
    let units: [String: Double]
    /// Unit used when the user gave none ("dal" → 1 bowl).
    let defaultUnit: String
    let isLiquid: Bool

    /// Grams of one default serving.
    var servingGrams: Double { units[defaultUnit] ?? NutritionUnits.genericGrams[defaultUnit] ?? 100 }

    func macros(grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f)
    }
}

nonisolated struct Macros: Sendable, Hashable, Codable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }

    func scaled(_ factor: Double) -> Macros {
        Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
}

/// Bundled nutrition table v1 — the offline backbone of text, voice, preset and
/// photo logging on every device, including phones without Apple Intelligence.
///
/// Provenance: `lifeos-curated-v1`. Values are typical home-recipe estimates per
/// 100 g (USDA FoodData Central for generic foods; common Indian recipe
/// composition for dishes). F02 §4.3: replace/extend with a licensed Indian
/// composition table (IFCT 2017) once legal confirms licensing — the resolver
/// only depends on this shape. Entries are deliberately conservative for oil.
nonisolated enum FoodCatalog {
    static let version = "lifeos-curated-v1"

    // swiftlint:disable line_length
    private static func f(_ id: String, _ aliases: [String], _ c: FoodRecord.Category, _ kcal: Double, _ p: Double, _ cb: Double, _ fat: Double,
                          _ units: [String: Double], _ defaultUnit: String, liquid: Bool = false) -> FoodRecord {
        FoodRecord(id: id, name: id, aliases: aliases, category: c, kcal: kcal, protein: p, carbs: cb, fat: fat,
                   units: units, defaultUnit: defaultUnit, isLiquid: liquid)
    }

    static let all: [FoodRecord] = [
        // MARK: Breads
        f("roti", ["chapati", "chapatti", "phulka", "fulka", "rotli", "wheat roti"], .bread, 297, 9.8, 46, 8.0, ["piece": 40], "piece"),
        f("tandoori roti", ["tandoori"], .bread, 290, 9, 55, 3.5, ["piece": 60], "piece"),
        f("butter roti", [], .bread, 340, 8.5, 44, 14, ["piece": 45], "piece"),
        f("paratha", ["plain paratha", "parantha", "prantha"], .bread, 326, 6.5, 45, 13, ["piece": 80], "piece"),
        f("aloo paratha", ["aloo parantha", "potato paratha"], .bread, 260, 5.5, 36, 10.5, ["piece": 130], "piece"),
        f("paneer paratha", ["paneer parantha"], .bread, 285, 10, 32, 13, ["piece": 130], "piece"),
        f("gobi paratha", ["gobhi paratha", "cauliflower paratha"], .bread, 240, 5.5, 33, 9.5, ["piece": 120], "piece"),
        f("methi thepla", ["thepla", "methi paratha"], .bread, 320, 8.5, 42, 13, ["piece": 45], "piece"),
        f("naan", ["plain naan"], .bread, 300, 9, 52, 6, ["piece": 90], "piece"),
        f("butter naan", [], .bread, 320, 8.5, 50, 9.5, ["piece": 100], "piece"),
        f("garlic naan", [], .bread, 315, 8.5, 50, 9, ["piece": 100], "piece"),
        f("kulcha", ["amritsari kulcha"], .bread, 300, 8, 48, 8.5, ["piece": 100], "piece"),
        f("puri", ["poori"], .bread, 350, 6.5, 44, 17, ["piece": 25], "piece"),
        f("bhatura", ["bhature"], .bread, 340, 7.5, 45, 15, ["piece": 80], "piece"),
        f("missi roti", [], .bread, 290, 11, 45, 7.5, ["piece": 50], "piece"),
        f("bajra roti", ["bajra rotla", "bajra bhakri"], .bread, 290, 8.5, 55, 4.5, ["piece": 50], "piece"),
        f("jowar roti", ["jowar bhakri"], .bread, 280, 8, 58, 2.5, ["piece": 50], "piece"),
        f("bread", ["white bread", "bread slice"], .bread, 265, 9, 49, 3.2, ["slice": 28, "piece": 28], "slice"),
        f("brown bread", ["whole wheat bread", "multigrain bread"], .bread, 250, 12, 43, 3.5, ["slice": 30, "piece": 30], "slice"),
        f("toast", ["bread toast"], .bread, 290, 9.5, 54, 3.5, ["slice": 26, "piece": 26], "slice"),
        f("pav", ["pao", "bun", "bread roll", "ladi pav"], .bread, 270, 8.5, 50, 4, ["piece": 40], "piece"),
        f("bagel", [], .bread, 257, 10, 50, 1.6, ["piece": 100], "piece"),
        f("croissant", [], .bread, 406, 8.2, 45, 21, ["piece": 60], "piece"),
        f("tortilla", ["wrap"], .bread, 310, 8.5, 52, 7.5, ["piece": 45], "piece"),

        // MARK: Rice dishes
        f("rice", ["white rice", "steamed rice", "chawal", "plain rice", "boiled rice", "cooked rice"], .rice, 130, 2.7, 28, 0.3, ["bowl": 150, "cup": 160, "plate": 250], "bowl"),
        f("brown rice", [], .rice, 123, 2.7, 26, 1, ["bowl": 150, "cup": 160, "plate": 250], "bowl"),
        f("jeera rice", ["cumin rice"], .rice, 170, 3, 29, 4.5, ["bowl": 150, "cup": 160, "plate": 250], "bowl"),
        f("veg pulao", ["pulao", "vegetable pulao", "pulav", "veg pulav"], .rice, 160, 3.5, 26, 4.8, ["bowl": 150, "cup": 160, "plate": 250], "plate"),
        f("chicken biryani", ["biryani", "biriyani", "chicken biriyani"], .rice, 200, 9, 24, 7.5, ["bowl": 200, "plate": 350], "plate"),
        f("mutton biryani", ["mutton biriyani", "gosht biryani"], .rice, 220, 10, 22, 10, ["bowl": 200, "plate": 350], "plate"),
        f("veg biryani", ["vegetable biryani"], .rice, 170, 4, 27, 5.5, ["bowl": 200, "plate": 350], "plate"),
        f("egg biryani", [], .rice, 190, 7.5, 24, 7, ["bowl": 200, "plate": 350], "plate"),
        f("khichdi", ["khichri", "dal khichdi", "moong dal khichdi"], .rice, 120, 4.5, 20, 2.5, ["bowl": 200, "katori": 150, "plate": 300], "bowl"),
        f("curd rice", ["dahi chawal", "thayir sadam"], .rice, 135, 3.5, 20, 4.5, ["bowl": 200, "plate": 300], "bowl"),
        f("lemon rice", [], .rice, 175, 3, 28, 5.5, ["bowl": 150, "plate": 250], "plate"),
        f("fried rice", ["veg fried rice"], .rice, 175, 3.8, 27, 5.8, ["bowl": 200, "plate": 300], "plate"),
        f("egg fried rice", [], .rice, 185, 6, 25, 6.8, ["bowl": 200, "plate": 300], "plate"),
        f("rajma chawal", ["rajma rice"], .rice, 135, 5, 22, 3, ["plate": 350, "bowl": 250], "plate"),
        f("chole chawal", ["chole rice"], .rice, 150, 5, 23, 4.2, ["plate": 350, "bowl": 250], "plate"),
        f("dal chawal", ["dal rice"], .rice, 125, 4.5, 22, 2.2, ["plate": 350, "bowl": 250], "plate"),

        // MARK: Dals & legumes
        f("dal", ["daal", "dhal", "yellow dal", "toor dal", "arhar dal", "dal tadka", "tadka dal", "lentil", "lentils", "lentil soup", "moong dal", "masoor dal"], .dal, 105, 6, 14, 3, ["bowl": 150, "katori": 150, "cup": 240], "bowl"),
        f("dal makhani", ["maa ki dal", "dal makhni"], .dal, 150, 6, 15, 7.5, ["bowl": 150, "katori": 150, "cup": 240], "bowl"),
        f("dal fry", [], .dal, 120, 6, 14, 4.5, ["bowl": 150, "katori": 150], "bowl"),
        f("rajma", ["rajma masala", "kidney beans curry", "kidney beans"], .dal, 130, 6.5, 17, 4, ["bowl": 150, "katori": 150], "bowl"),
        f("chole", ["chana masala", "chhole", "chickpea curry", "chole masala", "chana", "chickpeas", "pindi chole"], .dal, 150, 7, 19, 5, ["bowl": 150, "katori": 150], "bowl"),
        f("sambar", ["sambhar"], .dal, 65, 3, 9, 2, ["bowl": 150, "katori": 150, "cup": 240], "bowl"),
        f("kadhi", ["kadhi pakora", "punjabi kadhi"], .dal, 95, 3.5, 8, 5.5, ["bowl": 150, "katori": 150], "bowl"),
        f("sprouts", ["moong sprouts", "sprouts salad", "sprout salad"], .dal, 70, 6, 10, 1, ["bowl": 100, "cup": 100, "katori": 100], "bowl"),
        f("sundal", ["chana sundal"], .dal, 140, 7.5, 20, 3.5, ["bowl": 100], "bowl"),

        // MARK: Veg curries & sabzi
        f("paneer butter masala", ["butter paneer", "paneer makhani", "paneer makhanwala"], .vegCurry, 230, 9, 9, 18, ["bowl": 150, "katori": 150], "bowl"),
        f("palak paneer", ["saag paneer"], .vegCurry, 165, 8, 6, 12, ["bowl": 150, "katori": 150], "bowl"),
        f("kadai paneer", ["kadhai paneer"], .vegCurry, 200, 9, 8, 15, ["bowl": 150, "katori": 150], "bowl"),
        f("matar paneer", ["mutter paneer"], .vegCurry, 170, 8, 9, 11.5, ["bowl": 150, "katori": 150], "bowl"),
        f("shahi paneer", [], .vegCurry, 240, 9, 9, 19, ["bowl": 150, "katori": 150], "bowl"),
        f("paneer bhurji", [], .vegCurry, 250, 14, 6, 19, ["bowl": 120, "katori": 120, "plate": 150], "bowl"),
        f("paneer tikka", [], .vegCurry, 240, 16, 6, 17, ["piece": 30, "plate": 180], "plate"),
        f("aloo gobi", ["aloo gobhi"], .vegCurry, 100, 2.5, 12, 5, ["bowl": 150, "katori": 150], "bowl"),
        f("aloo sabzi", ["aloo ki sabzi", "potato curry", "aloo bhaji", "potato sabzi"], .vegCurry, 115, 2, 16, 5, ["bowl": 150, "katori": 150], "bowl"),
        f("bhindi masala", ["bhindi", "okra", "bhindi fry"], .vegCurry, 110, 2.5, 10, 7, ["bowl": 120, "katori": 120], "bowl"),
        f("baingan bharta", ["bharta", "baingan"], .vegCurry, 95, 2, 9, 6, ["bowl": 150, "katori": 150], "bowl"),
        f("mix veg", ["mixed vegetable curry", "mix veg sabzi", "mixed veg", "sabzi", "sabji", "vegetable curry"], .vegCurry, 95, 2.5, 10, 5, ["bowl": 150, "katori": 150], "bowl"),
        f("malai kofta", [], .vegCurry, 230, 5.5, 14, 17, ["bowl": 150, "piece": 50], "bowl"),
        f("pav bhaji", ["bhaji"], .vegCurry, 150, 3.5, 18, 7.5, ["plate": 250, "bowl": 150], "plate"),
        f("aloo matar", ["aloo mutter"], .vegCurry, 110, 3, 15, 4.5, ["bowl": 150, "katori": 150], "bowl"),
        f("dum aloo", [], .vegCurry, 140, 2.5, 15, 8, ["bowl": 150, "katori": 150], "bowl"),
        f("cabbage sabzi", ["patta gobhi", "cabbage poriyal"], .vegCurry, 75, 2, 8, 4, ["bowl": 120, "katori": 120], "bowl"),
        f("veg kurma", ["vegetable korma", "veg korma"], .vegCurry, 130, 3, 11, 8.5, ["bowl": 150], "bowl"),

        // MARK: Non-veg
        f("chicken curry", ["chicken masala", "chicken gravy"], .nonVegCurry, 165, 15, 4, 10, ["bowl": 150, "katori": 150, "piece": 60], "bowl"),
        f("butter chicken", ["murgh makhani", "chicken makhani"], .nonVegCurry, 210, 14, 6, 14.5, ["bowl": 150, "katori": 150], "bowl"),
        f("chicken tikka", ["chicken tikka kebab"], .nonVegCurry, 165, 25, 3, 6, ["piece": 30, "plate": 180], "piece"),
        f("tandoori chicken", [], .nonVegCurry, 180, 25, 3, 7.5, ["piece": 110, "plate": 250], "piece"),
        f("chicken tikka masala", [], .nonVegCurry, 190, 14, 6, 12, ["bowl": 150, "katori": 150], "bowl"),
        f("mutton curry", ["mutton masala", "goat curry", "lamb curry", "rogan josh", "gosht"], .nonVegCurry, 200, 15, 4, 14, ["bowl": 150, "katori": 150], "bowl"),
        f("fish curry", ["machli curry", "fish masala"], .nonVegCurry, 140, 14, 4, 7.5, ["bowl": 150, "katori": 150, "piece": 70], "bowl"),
        f("fish fry", ["fried fish", "tawa fish"], .nonVegCurry, 220, 20, 6, 13, ["piece": 80], "piece"),
        f("egg curry", ["anda curry"], .nonVegCurry, 150, 8.5, 5, 11, ["bowl": 150, "katori": 150], "bowl"),
        f("keema", ["kheema", "mutton keema", "chicken keema"], .nonVegCurry, 200, 15, 5, 13.5, ["bowl": 150, "katori": 150], "bowl"),
        f("prawn curry", ["shrimp curry", "jhinga"], .nonVegCurry, 130, 14, 4, 6.5, ["bowl": 150], "bowl"),
        f("grilled chicken breast", ["chicken breast", "grilled chicken", "boiled chicken"], .nonVegCurry, 165, 31, 0, 3.6, ["piece": 150, "plate": 200], "piece"),
        f("chicken seekh kebab", ["seekh kebab", "kebab"], .nonVegCurry, 220, 17, 5, 15, ["piece": 50], "piece"),

        // MARK: South Indian & breakfast
        f("idli", ["idly", "rice idli"], .southIndian, 135, 4, 28, 0.5, ["piece": 40], "piece"),
        f("dosa", ["plain dosa", "dosai"], .southIndian, 165, 3.8, 27, 4.5, ["piece": 90], "piece"),
        f("masala dosa", [], .southIndian, 165, 3.5, 24, 6.2, ["piece": 180], "piece"),
        f("rava dosa", [], .southIndian, 190, 3.5, 28, 7, ["piece": 100], "piece"),
        f("uttapam", ["uthappam", "onion uttapam"], .southIndian, 160, 4.5, 26, 4.5, ["piece": 120], "piece"),
        f("medu vada", ["vada", "vadai", "uddina vada"], .southIndian, 290, 9, 30, 15, ["piece": 50], "piece"),
        f("appam", [], .southIndian, 150, 2.5, 30, 2, ["piece": 60], "piece"),
        f("pongal", ["ven pongal"], .southIndian, 155, 4.5, 22, 5.5, ["bowl": 200], "bowl"),
        f("upma", ["rava upma", "uppittu"], .southIndian, 150, 3.5, 22, 5.5, ["bowl": 200, "plate": 200, "katori": 150], "bowl"),
        f("poha", ["kanda poha", "aval", "pohe"], .southIndian, 160, 3, 26, 5, ["plate": 200, "bowl": 180], "plate"),
        f("coconut chutney", ["nariyal chutney"], .condiment, 210, 2.5, 8, 19, ["tbsp": 15, "bowl": 50, "katori": 50], "katori"),
        f("chutney", ["tomato chutney", "onion chutney"], .condiment, 120, 2, 12, 7, ["tbsp": 15, "bowl": 50, "katori": 50], "tbsp"),
        f("green chutney", ["pudina chutney", "mint chutney", "hari chutney", "coriander chutney"], .condiment, 60, 2.5, 8, 2, ["tbsp": 15, "katori": 50], "tbsp"),
        f("dhokla", ["khaman dhokla", "khaman"], .snack, 160, 6.5, 24, 4, ["piece": 30], "piece"),
        f("sabudana khichdi", ["sabudana", "sago khichdi"], .southIndian, 180, 2, 28, 6.5, ["bowl": 200, "plate": 200], "bowl"),
        f("misal", ["misal pav", "usal"], .vegCurry, 140, 6, 15, 6, ["bowl": 250, "plate": 300], "bowl"),
        f("pesarattu", ["moong dal dosa", "green gram dosa"], .southIndian, 160, 7.5, 22, 4.5, ["piece": 100], "piece"),
        f("puttu", [], .southIndian, 165, 3.5, 35, 1, ["piece": 100, "plate": 200], "piece"),
        f("chicken 65", ["chicken sixty five", "chilli chicken"], .nonVegCurry, 250, 20, 10, 14.5, ["plate": 200, "piece": 25], "plate"),
        f("chilli paneer", ["paneer chilli"], .vegCurry, 230, 11, 12, 15.5, ["plate": 200, "bowl": 150], "plate"),
        f("gobi manchurian", ["manchurian", "veg manchurian", "gobhi manchurian"], .vegCurry, 190, 3.5, 22, 10, ["plate": 200, "bowl": 150], "plate"),
        f("idiyappam", ["string hoppers"], .southIndian, 150, 2.5, 33, 0.5, ["piece": 30], "piece"),

        // MARK: Snacks & street food
        f("samosa", ["aloo samosa", "veg samosa"], .snack, 310, 5, 32, 18, ["piece": 80], "piece"),
        f("kachori", ["khasta kachori", "dal kachori"], .snack, 400, 7, 40, 23, ["piece": 60], "piece"),
        f("pakora", ["pakoda", "bhajji", "bhaji pakora", "onion pakora", "kanda bhaji"], .snack, 315, 7, 30, 18, ["piece": 20, "plate": 120], "plate"),
        f("vada pav", ["wada pav"], .snack, 290, 6, 40, 12, ["piece": 150], "piece"),
        f("pani puri", ["golgappa", "gol gappa", "puchka", "pani poori"], .snack, 180, 3, 28, 6, ["piece": 15, "plate": 120], "plate"),
        f("bhel puri", ["bhel"], .snack, 210, 5, 33, 6.5, ["plate": 150, "bowl": 150], "plate"),
        f("sev puri", [], .snack, 270, 5.5, 32, 13, ["plate": 120], "plate"),
        f("dahi puri", [], .snack, 200, 5, 28, 7.5, ["plate": 150], "plate"),
        f("aloo tikki", ["tikki"], .snack, 220, 3.5, 28, 10.5, ["piece": 60], "piece"),
        f("momo", ["momos", "dumpling", "veg momo", "chicken momo"], .snack, 200, 7, 28, 6.5, ["piece": 25, "plate": 200], "plate"),
        f("spring roll", ["veg spring roll"], .snack, 250, 4.5, 30, 12.5, ["piece": 50], "piece"),
        f("cutlet", ["veg cutlet"], .snack, 230, 4.5, 27, 11.5, ["piece": 60], "piece"),
        f("maggi", ["maggi noodles", "instant noodles", "maggie", "noodles"], .packaged, 140, 3.2, 19, 5.6, ["packet": 300, "bowl": 300, "plate": 300], "packet"),
        f("chowmein", ["chow mein", "hakka noodles", "veg noodles"], .fastFood, 165, 4.5, 24, 6, ["plate": 250, "bowl": 250], "plate"),
        f("namkeen", ["mixture", "bhujia", "aloo bhujia", "chivda"], .snack, 520, 13, 48, 31, ["handful": 30, "bowl": 50, "katori": 50], "handful"),
        f("makhana", ["fox nuts", "roasted makhana"], .snack, 350, 9.7, 77, 0.5, ["bowl": 30, "cup": 30, "handful": 15], "bowl"),
        f("chips", ["potato chips", "lays", "crisps", "wafers"], .packaged, 540, 6.5, 52, 34, ["packet": 52, "handful": 25], "packet"),
        f("popcorn", [], .snack, 390, 12, 78, 4.5, ["cup": 8, "bowl": 30], "bowl"),

        // MARK: Sweets
        f("gulab jamun", ["gulab jamoon"], .sweet, 325, 4, 50, 12.5, ["piece": 40], "piece"),
        f("jalebi", ["jilebi"], .sweet, 400, 3, 64, 15, ["piece": 30, "plate": 100], "piece"),
        f("rasgulla", ["rosogolla", "rasagola"], .sweet, 185, 4, 39, 1.8, ["piece": 50], "piece"),
        f("ladoo", ["laddu", "besan ladoo", "boondi ladoo", "motichoor ladoo"], .sweet, 450, 7, 55, 22, ["piece": 40], "piece"),
        f("barfi", ["burfi", "kaju katli", "kaju barfi"], .sweet, 420, 8, 55, 19, ["piece": 25], "piece"),
        f("kheer", ["rice kheer", "payasam", "rice pudding", "chawal ki kheer"], .sweet, 140, 3.8, 21, 4.5, ["bowl": 150, "cup": 150, "katori": 150], "bowl"),
        f("halwa", ["sooji halwa", "suji halwa", "sheera", "gajar halwa", "gajar ka halwa"], .sweet, 330, 4, 45, 15, ["bowl": 100, "katori": 100, "plate": 120], "katori"),
        f("rasmalai", ["ras malai"], .sweet, 210, 6.5, 26, 9, ["piece": 60], "piece"),
        f("ice cream", ["icecream", "kulfi"], .sweet, 207, 3.5, 24, 11, ["scoop": 65, "cup": 100, "piece": 70], "scoop"),
        f("chocolate", ["dairy milk", "chocolate bar"], .sweet, 535, 7.5, 59, 30, ["bar": 40, "piece": 10], "bar"),
        f("cake", ["chocolate cake", "pastry"], .sweet, 370, 5, 50, 17, ["slice": 80, "piece": 80], "slice"),
        f("brownie", [], .sweet, 465, 5.5, 58, 24, ["piece": 60], "piece"),
        f("muffin", ["blueberry muffin", "chocolate muffin"], .sweet, 380, 5.5, 52, 17, ["piece": 110], "piece"),
        f("donut", ["doughnut"], .sweet, 420, 5, 50, 23, ["piece": 60], "piece"),
        f("cookie", ["cookies"], .sweet, 490, 5.5, 64, 24, ["piece": 15], "piece"),

        // MARK: Beverages
        f("chai", ["tea", "masala chai", "milk tea", "cutting chai", "ginger tea", "adrak chai"], .beverage, 55, 1.6, 7.5, 2, ["cup": 150, "glass": 200, "mug": 250], "cup", liquid: true),
        f("black tea", ["green tea", "lemon tea", "herbal tea"], .beverage, 1, 0, 0.3, 0, ["cup": 200, "mug": 250], "cup", liquid: true),
        f("coffee", ["filter coffee", "milk coffee", "south indian coffee"], .beverage, 60, 1.8, 8, 2.2, ["cup": 150, "glass": 200, "mug": 250], "cup", liquid: true),
        f("black coffee", ["americano", "espresso"], .beverage, 2, 0.1, 0, 0, ["cup": 200, "mug": 250, "shot": 30], "cup", liquid: true),
        f("latte", ["cafe latte", "cappuccino", "flat white"], .beverage, 55, 3.2, 4.8, 2.6, ["cup": 350, "mug": 350, "small": 240, "medium": 350, "large": 470], "cup", liquid: true),
        f("caramel frappuccino", ["frappuccino", "frappe", "cold coffee"], .beverage, 85, 1.3, 14, 2.8, ["cup": 470, "glass": 300, "small": 350, "medium": 470, "large": 590], "cup", liquid: true),
        f("lassi", ["sweet lassi", "mango lassi"], .beverage, 95, 3, 15, 2.5, ["glass": 250, "cup": 200], "glass", liquid: true),
        f("chaas", ["buttermilk", "chhach", "mattha", "salted lassi"], .beverage, 25, 1.5, 2.5, 1, ["glass": 250, "cup": 200], "glass", liquid: true),
        f("nimbu pani", ["lemonade", "lemon water", "shikanji", "nimbu paani"], .beverage, 40, 0, 10, 0, ["glass": 250], "glass", liquid: true),
        f("coconut water", ["nariyal pani"], .beverage, 19, 0.7, 3.7, 0.2, ["glass": 250, "piece": 300], "glass", liquid: true),
        f("orange juice", ["juice", "fruit juice", "mosambi juice", "sweet lime juice"], .beverage, 45, 0.7, 10.4, 0.2, ["glass": 250, "cup": 240], "glass", liquid: true),
        f("cola", ["coke", "coca cola", "pepsi", "thums up", "soft drink", "soda"], .beverage, 42, 0, 10.6, 0, ["can": 330, "glass": 250, "bottle": 500], "can", liquid: true),
        f("coke zero", ["diet coke", "coca cola zero", "coca-cola zero", "pepsi black", "diet soda"], .beverage, 0.3, 0, 0, 0, ["can": 330, "glass": 250, "bottle": 500], "can", liquid: true),
        f("beer", ["lager"], .beverage, 43, 0.5, 3.6, 0, ["bottle": 650, "can": 330, "glass": 330, "pint": 470], "bottle", liquid: true),
        f("wine", ["red wine", "white wine"], .beverage, 85, 0.1, 2.6, 0, ["glass": 150], "glass", liquid: true),
        f("whisky", ["whiskey", "vodka", "rum", "gin", "peg"], .beverage, 250, 0, 0, 0, ["peg": 30, "shot": 30, "glass": 60], "peg", liquid: true),
        f("smoothie", ["banana smoothie", "protein smoothie"], .beverage, 75, 2.5, 13, 1.2, ["glass": 300], "glass", liquid: true),
        f("milkshake", ["shake", "chocolate shake", "banana shake"], .beverage, 110, 3.5, 17, 3, ["glass": 300], "glass", liquid: true),
        f("water", ["paani", "pani"], .beverage, 0, 0, 0, 0, ["glass": 250, "bottle": 1000], "glass", liquid: true),

        // MARK: Dairy
        f("milk", ["doodh", "whole milk", "full cream milk", "toned milk"], .dairy, 61, 3.2, 4.8, 3.3, ["glass": 250, "cup": 240], "glass", liquid: true),
        f("skimmed milk", ["skim milk", "low fat milk"], .dairy, 35, 3.4, 5, 0.2, ["glass": 250, "cup": 240], "glass", liquid: true),
        f("curd", ["dahi", "yogurt", "yoghurt", "plain curd", "plain yogurt"], .dairy, 61, 3.5, 4.7, 3.3, ["bowl": 150, "katori": 150, "cup": 240], "bowl"),
        f("greek yogurt", ["hung curd"], .dairy, 97, 9, 3.9, 5, ["bowl": 150, "cup": 200], "bowl"),
        f("raita", ["cucumber raita", "boondi raita", "veg raita"], .dairy, 70, 3, 6, 3.5, ["bowl": 100, "katori": 100], "katori"),
        f("paneer", ["cottage cheese", "raw paneer"], .dairy, 265, 18, 3.5, 20, ["piece": 25, "cube": 25], "piece"),
        f("cheese", ["cheese slice", "amul cheese slice", "processed cheese", "cheddar"], .dairy, 310, 20, 4, 24, ["slice": 20, "piece": 20, "cube": 20], "slice"),
        f("ghee", ["desi ghee", "clarified butter"], .fat, 900, 0, 0, 100, ["tsp": 5, "tbsp": 14, "spoon": 5], "tsp"),
        f("butter", ["amul butter", "makhan"], .fat, 717, 0.9, 0.1, 81, ["tsp": 5, "tbsp": 14, "piece": 10, "cube": 10], "tsp"),
        f("cream", ["malai", "fresh cream"], .dairy, 340, 2.1, 2.8, 36, ["tbsp": 15], "tbsp"),

        // MARK: Eggs
        f("egg", ["boiled egg", "anda", "eggs", "hard boiled egg", "whole egg"], .egg, 155, 12.6, 1.1, 10.6, ["piece": 50], "piece"),
        f("fried egg", ["sunny side up", "egg fry"], .egg, 196, 13.6, 0.8, 15, ["piece": 55], "piece"),
        f("scrambled egg", ["scrambled eggs", "egg bhurji", "anda bhurji", "bhurji"], .egg, 170, 11, 2, 13, ["piece": 60, "plate": 150], "piece"),
        f("omelette", ["omelet", "masala omelette", "anda omelette"], .egg, 155, 10.5, 2.5, 11.5, ["piece": 120], "piece"),
        f("egg white", ["egg whites"], .egg, 52, 11, 0.7, 0.2, ["piece": 33], "piece"),

        // MARK: Fruits
        f("banana", ["kela"], .fruit, 89, 1.1, 23, 0.3, ["piece": 118], "piece"),
        f("apple", ["seb"], .fruit, 52, 0.3, 14, 0.2, ["piece": 182], "piece"),
        f("orange", ["santra", "mosambi", "sweet lime"], .fruit, 47, 0.9, 12, 0.1, ["piece": 130], "piece"),
        f("mango", ["aam"], .fruit, 60, 0.8, 15, 0.4, ["piece": 200, "cup": 165, "bowl": 165], "piece"),
        f("papaya", ["papita"], .fruit, 43, 0.5, 11, 0.3, ["bowl": 150, "cup": 145, "slice": 100], "bowl"),
        f("watermelon", ["tarbooz"], .fruit, 30, 0.6, 7.6, 0.2, ["bowl": 150, "cup": 150, "slice": 280], "bowl"),
        f("grapes", ["angoor", "grape"], .fruit, 69, 0.7, 18, 0.2, ["bowl": 150, "cup": 150, "handful": 50], "bowl"),
        f("pomegranate", ["anar"], .fruit, 83, 1.7, 19, 1.2, ["piece": 280, "bowl": 150, "cup": 175], "bowl"),
        f("guava", ["amrood"], .fruit, 68, 2.6, 14, 1, ["piece": 100], "piece"),
        f("pineapple", [], .fruit, 50, 0.5, 13, 0.1, ["bowl": 150, "cup": 165, "slice": 85], "bowl"),
        f("strawberry", ["strawberries"], .fruit, 32, 0.7, 7.7, 0.3, ["cup": 150, "bowl": 150, "piece": 12], "cup"),
        f("fruit salad", ["mixed fruit", "fruit bowl", "fruits"], .fruit, 55, 0.7, 14, 0.2, ["bowl": 200, "cup": 200], "bowl"),
        f("dates", ["khajur", "date"], .fruit, 282, 2.5, 75, 0.4, ["piece": 8], "piece"),

        // MARK: Vegetables & salads
        f("salad", ["green salad", "veg salad", "kachumber", "cucumber salad"], .vegetable, 25, 1, 5, 0.2, ["bowl": 150, "plate": 150, "cup": 100], "bowl"),
        f("steamed broccoli", ["broccoli"], .vegetable, 35, 2.4, 7, 0.4, ["bowl": 150, "cup": 90], "bowl"),
        f("cucumber", ["kheera"], .vegetable, 15, 0.7, 3.6, 0.1, ["piece": 200], "piece"),
        f("boiled potato", ["potato", "aloo", "baked potato"], .vegetable, 87, 1.9, 20, 0.1, ["piece": 150], "piece"),
        f("sweet potato", ["shakarkandi"], .vegetable, 86, 1.6, 20, 0.1, ["piece": 130], "piece"),
        f("corn", ["sweet corn", "bhutta", "corn on the cob"], .vegetable, 96, 3.4, 21, 1.5, ["cup": 150, "piece": 100], "cup"),
        f("soup", ["tomato soup", "veg soup", "sweet corn soup", "manchow soup"], .vegetable, 45, 1.5, 7, 1.3, ["bowl": 250, "cup": 240], "bowl", liquid: true),
        f("chicken caesar salad", ["caesar salad"], .western, 150, 10, 6, 9.5, ["bowl": 300, "plate": 300], "bowl"),

        // MARK: Grains & cereals
        f("oatmeal", ["oats", "porridge", "masala oats", "dalia", "daliya", "overnight oats"], .grain, 71, 2.5, 12, 1.5, ["bowl": 250, "cup": 240], "bowl"),
        f("muesli", ["granola"], .grain, 380, 10, 66, 7, ["bowl": 50, "cup": 80], "bowl"),
        f("cornflakes", ["cereal", "corn flakes", "chocos"], .grain, 357, 7.5, 84, 0.4, ["bowl": 30, "cup": 28], "bowl"),
        f("pasta", ["spaghetti", "penne", "macaroni", "white sauce pasta", "red sauce pasta"], .western, 160, 5.5, 25, 4, ["plate": 250, "bowl": 220], "plate"),
        f("quinoa", [], .grain, 120, 4.4, 21, 1.9, ["bowl": 185, "cup": 185], "bowl"),

        // MARK: Western & fast food
        f("pizza", ["cheese pizza", "margherita pizza", "pepperoni pizza", "veg pizza"], .fastFood, 270, 11, 33, 10, ["slice": 107, "piece": 107], "slice"),
        f("burger", ["veg burger", "chicken burger", "hamburger", "cheeseburger"], .fastFood, 255, 11, 29, 10, ["piece": 200], "piece"),
        f("mcaloo tikki burger", ["mcaloo tikki", "aloo tikki burger"], .fastFood, 245, 5.5, 34, 9, ["piece": 150], "piece"),
        f("fries", ["french fries", "medium fries", "chips fries"], .fastFood, 312, 3.4, 41, 15, ["small": 80, "medium": 115, "large": 150, "plate": 115, "packet": 115], "medium"),
        f("sandwich", ["veg sandwich", "grilled sandwich", "club sandwich", "cheese sandwich"], .fastFood, 230, 8, 29, 9, ["piece": 150], "piece"),
        f("chicken sandwich", ["chicken sub", "subway"], .fastFood, 220, 13, 24, 7.5, ["piece": 200], "piece"),
        f("roll", ["kathi roll", "frankie", "chicken roll", "paneer roll", "shawarma", "wrap roll"], .fastFood, 240, 9.5, 27, 10.5, ["piece": 200], "piece"),
        f("fried chicken", ["kfc chicken", "chicken nuggets", "nuggets"], .fastFood, 290, 18, 13, 18.5, ["piece": 90], "piece"),
        f("hot dog", ["hotdog"], .fastFood, 290, 10, 24, 17, ["piece": 100], "piece"),
        f("taco", ["tacos"], .fastFood, 215, 9, 20, 11, ["piece": 100], "piece"),

        // MARK: Nuts & seeds
        f("almond", ["almonds", "badam"], .nuts, 579, 21, 22, 50, ["piece": 1.2, "handful": 25], "handful"),
        f("walnut", ["walnuts", "akhrot"], .nuts, 654, 15, 14, 65, ["piece": 4, "handful": 25], "handful"),
        f("cashew", ["cashews", "kaju"], .nuts, 553, 18, 30, 44, ["piece": 1.6, "handful": 25], "handful"),
        f("peanut", ["peanuts", "moongphali", "groundnuts"], .nuts, 567, 26, 16, 49, ["handful": 30, "bowl": 50], "handful"),
        f("mixed nuts", ["dry fruits", "nuts", "trail mix"], .nuts, 600, 18, 22, 52, ["handful": 30], "handful"),
        f("peanut butter", [], .nuts, 588, 25, 20, 50, ["tbsp": 16, "tsp": 5, "spoon": 16], "tbsp"),
        f("chia seeds", ["flax seeds", "seeds"], .nuts, 486, 17, 42, 31, ["tbsp": 12, "tsp": 4], "tbsp"),

        // MARK: Supplements & packaged
        f("whey protein", ["protein shake", "whey", "protein powder", "protein scoop"], .supplement, 380, 78, 8, 5, ["scoop": 32], "scoop"),
        f("protein bar", [], .supplement, 380, 30, 40, 12, ["bar": 60, "piece": 60], "bar"),
        f("parle-g biscuit", ["parle-g", "parle g", "parle g biscuit", "glucose biscuit"], .packaged, 455, 6.5, 77, 13.5, ["piece": 6.2, "packet": 70], "piece"),
        f("biscuit", ["biscuits", "marie biscuit", "digestive biscuit", "cream biscuit"], .packaged, 470, 7, 70, 18, ["piece": 8, "packet": 75], "piece"),
        f("rusk", ["toast rusk", "khari"], .packaged, 410, 11, 72, 8, ["piece": 12], "piece"),
        f("energy drink", ["red bull", "monster"], .beverage, 45, 0, 11, 0, ["can": 250], "can", liquid: true),

        // MARK: Fats & condiments
        f("oil", ["cooking oil", "olive oil", "mustard oil", "refined oil"], .fat, 884, 0, 0, 100, ["tsp": 4.5, "tbsp": 13.5], "tsp"),
        f("sugar", ["chini", "shakkar"], .condiment, 387, 0, 100, 0, ["tsp": 4, "tbsp": 12.5, "cube": 4], "tsp"),
        f("honey", ["shahad"], .condiment, 304, 0.3, 82, 0, ["tsp": 7, "tbsp": 21], "tsp"),
        f("jam", ["fruit jam"], .condiment, 278, 0.4, 69, 0.1, ["tsp": 7, "tbsp": 20], "tbsp"),
        f("ketchup", ["tomato ketchup", "tomato sauce"], .condiment, 112, 1.7, 26, 0.1, ["tbsp": 17, "tsp": 6, "packet": 9], "tbsp"),
        f("mayonnaise", ["mayo"], .condiment, 680, 1, 0.6, 75, ["tbsp": 14, "tsp": 5], "tbsp"),
        f("pickle", ["achar", "achaar", "mango pickle"], .condiment, 180, 1.5, 6, 17, ["tsp": 8, "tbsp": 20], "tsp"),
        f("papad", ["papadum", "pappadam", "appalam"], .condiment, 370, 26, 60, 3, ["piece": 12], "piece"),
    ]
    // swiftlint:enable line_length

    /// Lookup: normalised name/alias → record. Built once.
    static let index: [String: FoodRecord] = {
        var map: [String: FoodRecord] = [:]
        for record in all {
            for key in [record.name] + record.aliases {
                let normalised = FoodNameNormalizer.normalise(key)
                if map[normalised] == nil { map[normalised] = record }
            }
        }
        return map
    }()

    static func record(id: String) -> FoodRecord? { all.first { $0.id == id } }
}

/// Generic household measures used when a food has no specific entry (F02 §4.3).
nonisolated enum NutritionUnits {
    static let genericGrams: [String: Double] = [
        "g": 1, "kg": 1000, "ml": 1, "l": 1000,
        "bowl": 150, "katori": 150, "cup": 240, "mug": 250, "glass": 250, "plate": 250,
        "slice": 30, "piece": 50, "tbsp": 15, "tsp": 5, "spoon": 10, "scoop": 30, "handful": 30,
        "can": 330, "bottle": 500, "packet": 50, "bar": 40, "cube": 20, "peg": 30, "shot": 30, "pint": 470,
    ]

    /// Size words scale the food's default serving.
    static let sizeFactors: [String: Double] = ["small": 0.7, "medium": 1.0, "large": 1.4, "regular": 1.0]

    /// Units that are exact weights/volumes (full unit confidence).
    static let exactUnits: Set<String> = ["g", "kg", "ml", "l"]
}
