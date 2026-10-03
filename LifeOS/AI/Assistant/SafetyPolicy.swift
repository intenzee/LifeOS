import Foundation

/// The assistant's safety behaviours (F07 §7, F11 red-team, AI-310).
///
/// Runs before anything else on every turn, deterministically, on device, so it
/// works the same with or without a model. It decides *whether* to coach;
/// a model never gets to override it. Thresholds are deliberately narrow:
/// "plan dinner under 800 kcal" or "I killed it at the gym" are not flagged.
nonisolated enum SafetyPolicy {

    nonisolated enum Category: String, Sendable, Equatable, CaseIterable {
        case selfHarm
        case disorderedEating
        case compensatoryExercise
        case medicalEmergency
        case medical
        case promptInjection
        case outOfScope
    }

    nonisolated struct Verdict: Sendable, Equatable {
        var category: Category
        var reply: String
        /// No calorie numbers or plans in this turn (F07 §7).
        var suppressNumbers: Bool
        /// The UI should offer to hide calorie numbers (F08 §8). No such setting
        /// exists yet, so replies don't promise it; the flag is for when it lands.
        var offerHideNumbers: Bool
    }

    static func evaluate(_ raw: String, region: String? = nil, floorKcal: Double = 1_200) -> Verdict? {
        let t = " " + MemoryText.clean(raw).lowercased() + " "
        let resources = CrisisResources.for(region: region)

        if isSelfHarm(t) {
            return Verdict(category: .selfHarm, reply: """
                I'm really sorry you're feeling this way. You don't have to handle it alone. \
                Please reach out now: \(resources.crisis). If you're in immediate danger, call \(resources.emergency). \
                I'm here if you'd like to talk about something else too.
                """, suppressNumbers: true, offerHideNumbers: false)
        }
        if isMedicalEmergency(t) {
            return Verdict(category: .medicalEmergency, reply: """
                That could need urgent care. Please call \(resources.emergency) or get to the nearest emergency department now, \
                and don't wait to see if it passes.
                """, suppressNumbers: true, offerHideNumbers: false)
        }
        if isDisorderedEating(t, floorKcal: floorKcal) {
            return Verdict(category: .disorderedEating, reply: """
                I can't help with eating that little or cutting food out like that. It can harm your health and how you feel about food. \
                It sounds like things might be hard right now. A doctor or registered dietitian can help you find a plan that feels right\(resources.eatingSupport.map { ", and \($0)" } ?? ""). \
                If seeing calorie numbers isn't helping right now, it's okay to take a break from tracking.
                """, suppressNumbers: true, offerHideNumbers: true)
        }
        if isCompensatory(t) {
            return Verdict(category: .compensatoryExercise, reply: """
                You don't need to earn or burn off food. One meal doesn't undo anything, and exercise works best as something good for you, not a punishment. \
                If you'd like, I can help plan a steady, enjoyable week instead.
                """, suppressNumbers: true, offerHideNumbers: true)
        }
        if isMedical(t) {
            return Verdict(category: .medical, reply: """
                I can't advise on medicines, doses or diagnoses. Your doctor or pharmacist is the right person for that. \
                I can still help with meals, your budget and your training.
                """, suppressNumbers: false, offerHideNumbers: false)
        }
        if isInjection(t) {
            return Verdict(category: .promptInjection, reply: "I can't change how I work, but I'm happy to help with your meals, workouts and plans.",
                           suppressNumbers: false, offerHideNumbers: false)
        }
        if isOutOfScope(t) {
            return Verdict(category: .outOfScope, reply: "That's outside what I can help with. I'm here for your food, training, habits and day plans.",
                           suppressNumbers: false, offerHideNumbers: false)
        }
        return nil
    }

    // MARK: Detectors

    static func isSelfHarm(_ t: String) -> Bool {
        if Rx.matches(#"\b(dying for|killing it|killed it|kill it|kills me|to die for|killer (workout|burger|abs))\b"#, t)
            && !Rx.matches(#"\b(kill myself|want to die|end my life|suicid)"#, t) { return false }
        return Rx.matches(#"\b(kill myself|killing myself|end my life|ending my life|take my (own )?life|suicid\w*|want to die|wanna die|wish i (was|were) dead|better off dead|don'?t want to (live|be alive|exist)|no reason to live|self[- ]?harm\w*|hurt(ing)? myself|cut(ting)? myself|marna chahta|marna chahti|jeena nahi chahta|jeena nahi chahti)\b"#, t)
    }

    static func isMedicalEmergency(_ t: String) -> Bool {
        Rx.matches(#"\b(chest pain|chest is tight|can'?t breathe|cannot breathe|trouble breathing|fainted|passed out|blacked out|seizure|stroke|numb(ness)? (in|on) (my )?(face|arm)|anaphyla\w*|throat (is )?(closing|swelling)|swollen throat)\b"#, t)
    }

    static func isDisorderedEating(_ t: String, floorKcal: Double) -> Bool {
        // Purging and laxative/diuretic misuse.
        if Rx.matches(#"\b(make myself (throw up|vomit|sick)|throw(ing)? up after (eating|meals?)|purg(e|ing)|laxatives? (to|for) (lose|losing|weight)|diuretics? (to|for) (lose|losing|weight)|diet pills)\b"#, t) { return true }
        // Not eating at all for days, or deliberately starving.
        if Rx.matches(#"\b(stop eating( completely| altogether)?|not eat(ing)? (anything )?for (\d+|two|three|four|five|a few|several) days|eat nothing|starve myself|starving myself|skip all (my )?meals|only (drink|have) water for (\d+|two|three|several) days)\b"#, t) { return true }
        // "How do I stop being hungry" while restricting.
        if Rx.matches(#"\b(stop (being|feeling) hungry|suppress (my )?appetite|appetite suppressant|ignore (my )?hunger|trick (my )?(body|brain) into not)\b"#, t),
           Rx.matches(#"\b(diet|lose|losing|weight|calories|kcal|eat less|thin|skinny|fat)\b"#, t) { return true }
        // A daily target below the floor (not a single meal: "dinner under 800" is fine).
        let mealScoped = Rx.matches(#"\b(breakfast|lunch|dinner|snack|meal|supper|tiffin)\b"#, t) && !Rx.matches(#"\b(a day|per day|daily|each day|every day|all day)\b"#, t)
        if !mealScoped {
            for groups in Rx.allGroups(#"(\d{2,4})\s*(?:kcal|cal|cals|calories)"#, t) {
                guard groups.count > 1, let n = Double(groups[1]), n >= 100, n < floorKcal else { continue }
                if Rx.matches(#"\b(a day|per day|/day|daily|each day|every day|eat only|only eat|diet|target|limit|goal|to lose|plan|survive on|live on)\b"#, t) { return true }
            }
        }
        // Body-image distress paired with restriction.
        if Rx.matches(#"\b(i(?:'m| am) (so )?(fat|disgusting|gross|huge)|hate my body|feel (so )?fat|i look (fat|disgusting))\b"#, t),
           Rx.matches(#"\b(eat|eating|food|calories|kcal|diet|starve|skip|less)\b"#, t) { return true }
        return false
    }

    static func isCompensatory(_ t: String) -> Bool {
        Rx.matches(#"\b(burn (it |that |this |everything |all )?off|work (it |that |this )?off|make up for (eating|what i ate|the pizza|the cake)|earn (my|the|a) (food|meal|dinner|dessert|cheat)|punish myself|undo (the|what i ate|that meal|yesterday))\b"#, t)
            && Rx.matches(#"\b(ate|eat|eating|binge|binged|food|meals?|breakfast|lunch|dinner|snacks?|pizza|cake|dessert|calories|kcal|overate|cheat)\b"#, t)
    }

    static func isMedical(_ t: String) -> Bool {
        if Rx.matches(#"\b(dose|dosage|how (much|many) (mg|units|tablets|pills)|should i (stop|start|skip) (taking )?(my )?(\w+ )?(medicine|medication|meds|insulin|metformin|pills|tablets)|side effects? of|interact(ion)? with (my )?(medicine|medication)|prescri\w+|diagnos\w+|do i have (diabetes|cancer|thyroid|pcos)|is it (cancer|diabetes))\b"#, t) {
            return true
        }
        return Rx.matches(#"\b(metformin|insulin|ozempic|semaglutide|mounjaro|tirzepatide|thyroxine|statin|antibiotic|antidepressant|steroid)s?\b"#, t)
            && Rx.matches(#"\b(take|taking|stop|skip|how much|should i|can i|dose|with)\b"#, t)
    }

    static func isInjection(_ t: String) -> Bool {
        Rx.matches(#"\b(ignore|disregard|forget) (all |any |the |your |previous |prior |above |earlier )*(instructions|rules|prompt|guidelines|system)\b|\b(show|reveal|print|repeat) (me )?(your|the) (system )?(prompt|instructions)\b|\byou are now\b|\bdeveloper mode\b|\bjailbreak\b|\bpretend (you are|to be) (?!my)"#, t)
    }

    static func isOutOfScope(_ t: String) -> Bool {
        let lifeWords = #"\b(eat|ate|food|meal|kcal|calorie|protein|carb|fat|water|workout|gym|run|walk|weight|sleep|budget|todo|remind|plan|diet|recipe|breakfast|lunch|dinner|snack|steps|habit|streak)\b"#
        guard !Rx.matches(lifeWords, t) else { return false }
        return Rx.matches(#"\b(write (me )?(a |an |the )?(essay|poem|story|code|program|script|cover letter|email)|homework|assignment|python|javascript|java |c\+\+|sql|regex|debug (my|this)|stock tips?|crypto|bitcoin|who won|election|capital of|solve (this|the) (equation|problem))\b"#, t)
    }
}

/// Region-appropriate crisis resources. India first (the launch market).
nonisolated struct CrisisResources: Sendable, Equatable {
    var crisis: String
    var emergency: String
    var eatingSupport: String?

    static func `for`(region: String?) -> CrisisResources {
        switch (region ?? "IN").uppercased() {
        case "US":
            return CrisisResources(crisis: "the 988 Suicide & Crisis Lifeline (call or text 988)", emergency: "911",
                                   eatingSupport: "988 is there for distress about food too")
        case "GB", "UK":
            return CrisisResources(crisis: "Samaritans on 116 123 (free, any time)", emergency: "999",
                                   eatingSupport: "Beat's helpline (0808 801 0677) supports people with eating worries")
        case "IN":
            return CrisisResources(crisis: "Tele-MANAS on 14416 or 1-800-891-4416 (free, 24×7)", emergency: "112",
                                   eatingSupport: "Tele-MANAS (14416) can talk it through any time")
        default:
            return CrisisResources(crisis: "a local crisis line or someone you trust", emergency: "your local emergency number",
                                   eatingSupport: nil)
        }
    }
}
