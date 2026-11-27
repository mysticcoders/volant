import XCTest

@testable import VolantCore


/// Settings › Dictation › Spoken punctuation. The inputs are what the speech models wrote for
/// spoken punctuation (macOS 27.2.1, `say` voices Samantha, Paulina, Thomas, Anna, Alice and
/// Luciana): Apple's SpeechTranscriber, which leaves most names as words, and Parakeet (desktop
/// Hex's unified English model), which leaves every one.
final class SpokenPunctuationTests: XCTestCase {
    private func punctuated(_ text: String, _ language: String = "en-US") -> String {
        SpokenPunctuation.format(text, language: language)
    }

    func testEnglishFromSpeechTranscriber() {
        XCTAssertEqual(punctuated("That is amazing exclamation point."), "That is amazing!")
        XCTAssertEqual(punctuated("That is amazing exclamation mark."), "That is amazing!")
        XCTAssertEqual(punctuated("I came semicolon, I saw semicolon, I conquered."), "I came; I saw; I conquered.")
        XCTAssertEqual(punctuated("It was good dash really good."), "It was good – really good.")
        XCTAssertEqual(punctuated("It is a well hyphen known fact."), "It is a well-known fact.")
        XCTAssertEqual(punctuated("She said, open quote, hello, their close quote, and left."), "She said, “hello, their”, and left.")
        XCTAssertEqual(punctuated("Call me, open Paren after lunch close, Paren, please."), "Call me, (after lunch), please.")
        XCTAssertEqual(punctuated("Wait for it, ellipsis."), "Wait for it…")
        XCTAssertEqual(punctuated("Feeling great hashtag blessed."), "Feeling great #blessed.")
        XCTAssertEqual(punctuated("Great job, Smiley."), "Great job :-)")
        XCTAssertEqual(punctuated("It is John Apostrophe S Carr."), "It is John's Carr.")
        XCTAssertEqual(punctuated("Open parenthesis, just getting close parenthesis."), "(just getting).")
        XCTAssertEqual(punctuated("Thanks so much, exclamation point CU tomorrow period."), "Thanks so much! CU tomorrow.")
        XCTAssertEqual(
            punctuated("Okay, comma, so here is the thing, comment, I can't make it."),
            "Okay, so here is the thing, comment, I can't make it."
        )
        XCTAssertEqual(punctuated("I'll be there at noon, see you soon."), "I'll be there at noon, see you soon.", "converted already")
    }

    func testEnglishFromParakeet() {
        XCTAssertEqual(punctuated("I'll be there at noon, comma, see you soon, period"), "I'll be there at noon, see you soon.")
        XCTAssertEqual(punctuated("Are you coming tonight question mark?"), "Are you coming tonight?", "never doubled")
        XCTAssertEqual(punctuated("Here is the plan colon we leave at noon full stop."), "Here is the plan: we leave at noon.")
        XCTAssertEqual(punctuated("It is a well-hyphen known fact"), "It is a well-known fact")
        XCTAssertEqual(punctuated("She said open quote hello there close quote and left."), "She said “hello there” and left.")
        XCTAssertEqual(punctuated("Open parenthesis just kidding close parenthesis."), "(just kidding).")
        XCTAssertEqual(
            punctuated("Thanks so much exclamation point see you tomorrow period."),
            "Thanks so much! See you tomorrow."
        )
        XCTAssertEqual(punctuated("Hi Sarah comma\nthanks for the update period"), "Hi Sarah,\nthanks for the update.")
    }

    func testEnglishCommands() {
        XCTAssertEqual(punctuated("Hi Sarah comma how are you question mark"), "Hi Sarah, how are you?")
        XCTAssertEqual(punctuated("I'm on my way period see you soon"), "I'm on my way. See you soon")
        XCTAssertEqual(punctuated("Note to self colon buy milk"), "Note to self: buy milk")
        XCTAssertEqual(punctuated("Dear John comma"), "Dear John,")
        XCTAssertEqual(punctuated("Can you send it today question mark thanks"), "Can you send it today? Thanks")
        XCTAssertEqual(punctuated("Meet me at 5 period"), "Meet me at 5.")
        XCTAssertEqual(punctuated("Who are you going with question mark"), "Who are you going with?")
        XCTAssertEqual(punctuated("He said open quote no way close quote period"), "He said “no way”.")
        XCTAssertEqual(punctuated("He said quote I'm fine unquote and left"), "He said “I'm fine” and left")
        XCTAssertEqual(punctuated("Hashtag throwback"), "#throwback")
        XCTAssertEqual(punctuated("It costs dollar sign 50"), "It costs $50")
        XCTAssertEqual(punctuated("Escríbeme a ana arroba gmail.com", "es-ES"), "Escríbeme a ana@gmail.com")
        XCTAssertEqual(punctuated("Bring snacks open paren chips or pretzels close paren"), "Bring snacks (chips or pretzels)")
        XCTAssertEqual(punctuated("Love you smiley face"), "Love you :-)")
        XCTAssertEqual(punctuated("Okay comma sounds good period"), "Okay, sounds good.")
        XCTAssertEqual(punctuated("Thanks exclamation point exclamation point"), "Thanks!")
    }

    /// Apple's DictationTranscriber writes the marks itself; its text passes through.
    func testDictationTranscriberTextStays() {
        for text in [
            "That is amazing!", "Here is the plan: we leave at noon.", "I came; I saw; I conquered",
            "It was good – really good", "She said \"hello there\" and left", "Call me (after lunch) please",
            "Wait for it…", "Email me a john@gmail.com", "Feeling great. #Blessed.", "Great job :-)",
            "It is John's car", "Hi Sarah,\nThanks for the update.", "He has a? Tattoo on his arm.",
            "Thanks so much! See you tomorrow.",
        ] {
            XCTAssertEqual(punctuated(text), text)
        }
    }

    func testSpanish() {
        XCTAssertEqual(punctuated("Llego mañana, punto nos vemos", "es-ES"), "Llego mañana. Nos vemos")
        XCTAssertEqual(punctuated("Dijo abrir comillas sola, cerrar comillas si se fue.", "es-ES"), "Dijo “sola” si se fue.")
        XCTAssertEqual(
            punctuated("Llámame a abrir paréntesis después de comer, cerrar paréntesis.", "es-MX"),
            "Llámame a (después de comer)."
        )
        XCTAssertEqual(punctuated("Espera puntos suspensivos.", "es-ES"), "Espera…")
        XCTAssertEqual(
            punctuated("Abrir signo de interrogación vienes cerrar signo de interrogación", "es-ES"),
            "¿vienes?"
        )
        XCTAssertEqual(punctuated("Hola coma Juan punto y aparte nos vemos", "es-ES"), "Hola, Juan.\n\nNos vemos")
        XCTAssertEqual(punctuated("Gracias coma nos vemos mañana punto", "es-ES"), "Gracias, nos vemos mañana.")
        XCTAssertEqual(punctuated("Vine punto y coma vi", "es-ES"), "Vine; vi")
        XCTAssertEqual(punctuated("Es genial signo de exclamación", "es-ES"), "Es genial!")
        XCTAssertEqual(punctuated("La lista dos puntos pan y leche", "es-ES"), "La lista dos puntos pan y leche", "two points, maybe")
    }

    func testFrench() {
        XCTAssertEqual(punctuated("Bonjour virgule comment ça va point d'interrogation", "fr-FR"), "Bonjour, comment ça va?")
        XCTAssertEqual(punctuated("Je suis venu, point, j'ai vu", "fr-FR"), "Je suis venu. J'ai vu")
        XCTAssertEqual(punctuated("Je suis venu point-virgule j'ai vu", "fr-FR"), "Je suis venu; j'ai vu")
        XCTAssertEqual(punctuated("C'est génial point d’exclamation", "fr-FR"), "C'est génial!")
        XCTAssertEqual(
            punctuated("Il a dit ouvrez les guillemets bonjour, fermez les guillemets", "fr-FR"),
            "Il a dit «bonjour»"
        )
        XCTAssertEqual(punctuated("Appelle-moi ouvrir la parenthèse après le déjeuner", "fr-CA"), "Appelle-moi (après le déjeuner")
    }

    func testGerman() {
        XCTAssertEqual(punctuated("Der Plan Doppelpunkt, wir gehen um 12.", "de-DE"), "Der Plan: wir gehen um 12.")
        XCTAssertEqual(punctuated("Er sagte Anführungszeichen Hallo, Abführungszeichen.", "de-DE"), "Er sagte „Hallo“.")
        XCTAssertEqual(
            punctuated("Er sagte Anführungszeichen unten Hallo, Anführungszeichen oben.", "de-DE"),
            "Er sagte „Hallo“."
        )
        XCTAssertEqual(punctuated("Ich kam Semikolon ich sah", "de-DE"), "Ich kam; ich sah")
        XCTAssertEqual(punctuated("Warte Auslassungspunkte", "de-DE"), "Warte…")
        XCTAssertEqual(punctuated("Ich komme morgen Punkt bis bald", "de-DE"), "Ich komme morgen. Bis bald")
        XCTAssertEqual(punctuated("Hallo Komma wie geht es dir Fragezeichen", "de-AT"), "Hallo, wie geht es dir?")
        XCTAssertEqual(punctuated("Danke für das Update Punkt", "de-DE"), "Danke für das Update.")
        XCTAssertEqual(punctuated("Ruf mich an Punkt", "de-DE"), "Ruf mich an.")
        XCTAssertEqual(punctuated("Ruf mich an Klammer auf nach dem Essen Klammer zu", "de-DE"), "Ruf mich an (nach dem Essen)")
    }

    func testItalian() {
        XCTAssertEqual(punctuated("Ciao virgola come stai punto interrogativo", "it-IT"), "Ciao, come stai?")
        XCTAssertEqual(punctuated("Chiamami, apri parentesi dopo pranzo)", "it-IT"), "Chiamami, (dopo pranzo)")
        XCTAssertEqual(punctuated("Ha detto apri virgolette ciao chiudi virgolette", "it-IT"), "Ha detto “ciao”")
        XCTAssertEqual(punctuated("Sono venuto punto e virgola ho visto", "it-IT"), "Sono venuto; ho visto")
        XCTAssertEqual(punctuated("È fantastico punto esclamativo", "it-IT"), "È fantastico!")
        XCTAssertEqual(punctuated("Arrivo domani punto a presto", "it-IT"), "Arrivo domani. A presto")
    }

    func testPortuguese() {
        XCTAssertEqual(punctuated("Olá vírgula tudo bem?", "pt-BR"), "Olá, tudo bem?")
        XCTAssertEqual(punctuated("Chego amanhã ponto final até logo.", "pt-BR"), "Chego amanhã. Até logo.")
        XCTAssertEqual(punctuated("Ele disse abre aspas ou lá fecha aspas.", "pt-BR"), "Ele disse “ou lá”.")
        XCTAssertEqual(
            punctuated("Me liga abre parênteses depois do almoço fecha parênteses.", "pt-PT"),
            "Me liga (depois do almoço)."
        )
        XCTAssertEqual(punctuated("Eu vim ponto e vírgula eu vi.", "pt-BR"), "Eu vim; eu vi.")
        XCTAssertEqual(punctuated("É incrível o ponto de exclamação!", "pt-BR"), "É incrível o ponto de exclamação!", "after an article")
    }

    /// Everyday sentences that use the names as words: none may change.
    func testProseStaysAsSaid() {
        let english = [
            "It was a long period of time.",
            "The comma is optional here.",
            "She put a dash of salt in the soup.",
            "He has a question mark tattoo on his arm.",
            "The colon is part of the digestive system.",
            "Put a period at the end of the sentence.",
            "I'm not sure what the hashtag is.",
            "The trial period ends tomorrow.",
            "There's a big question mark over his future.",
            "My period started this morning.",
            "We had a free period after lunch.",
            "The grace period is thirty days.",
            "Do you use the Oxford comma?",
            "She made a mad dash for the door.",
            "I watched a period drama last night.",
            "He was diagnosed with colon cancer.",
            "My dash cam caught the whole thing.",
            "Add a dash of lemon juice.",
            "The hyphen in that word is wrong.",
            "Use an apostrophe for possession.",
            "That hashtag is trending right now.",
            "What does the at sign mean in an email?",
            "He ended the call with a smiley face emoji.",
            "During that period we lived in Boston.",
            "The question mark key is broken.",
            "An exclamation point at the end feels too loud.",
            "Commas and periods go inside the quotes.",
            "Is that a comma or a period?",
            "I need a quote for the kitchen remodel.",
            "Can you quote me on that?",
            "He used air quotes around the word.",
            "The open quote was missing.",
            "It's a quote unquote expert opinion.",
            "The time period doesn't matter.",
            "He's in colon surgery right now.",
            "Every comma counts in a contract.",
            "That was the last period of the game.",
            "They scored in the third period.",
            "A semicolon joins two clauses.",
            "The ellipsis at the end looks passive aggressive.",
            "Click the dollar sign to see prices.",
            "Type the hashtag before the word.",
            "A smiley can soften a message.",
            "Draw a dash between the numbers.",
            "The comma-separated list is attached.",
            "The waiting period was annoying.",
            "Can you dash off a quick reply?",
            "We need to dash to the store.",
            "I'll dash home after work.",
            "This colon cleanse is a scam.",
            "Her period was late this month.",
            "What a period of growth for the company.",
            "The comma after Hi is optional.",
            "I love the Oxford comma debate.",
            "The quote from the plumber was too high.",
            "The ten-year period ended in June.",
            "That was a really tough period for us.",
            "It happened over a short period.",
            "The colon in the time looks wrong.",
            "Where is the question mark on this keyboard?",
            "Is there an exclamation mark in the title?",
            "My dog is called Dash.",
            "I'll text Dash later.",
            "George Smiley is a spy.",
            "We waited for a period of hours.",
            "The Jurassic period was long ago.",
            "Your period tracker sent a notification.",
            "Use a colon before a list.",
            "The dollar sign is missing.",
            "No comma needed.",
            "I used comma separated values.",
            "Period cramps are the worst.",
            "Comma placement matters.",
            "That smiley was a bit much.",
            "Leave the quote as it is.",
            "Write an exclamation point if you're excited.",
            "She's the period expert on the team.",
            "Hashtags are everywhere.",
            "Quote me if you want.",
            "He gave a quote to the press.",
            "In the past, period films were huge.",
            "Colon health is important.",
            "The first period starts at eight.",
            "Send a smiley to Mom.",
        ]
        let others: [(String, [String])] = [
            ("es-ES", [
                "El punto de vista es claro.",
                "La coma es opcional.",
                "Es un punto de encuentro.",
                "Entró en coma ayer.",
                "Tres coma cinco.",
                "Ganamos por dos puntos.",
                "Ese es el punto.",
                "Está en su punto.",
                "Hay dos puntos de vista.",
                "Escribió el guion de la película.",
                "Lo dijo entre comillas.",
                "Pon una coma aquí.",
                "El paciente sigue en coma.",
                "Llegamos al punto de partida.",
            ]),
            ("fr-FR", [
                "C'est un point important.",
                "La virgule est facultative.",
                "Deux points de vue différents.",
                "Le point de vue est clair.",
                "Il a marqué deux points.",
                "Mettez une virgule ici.",
                "Entre guillemets c'est faux.",
                "Un tiret suffit.",
                "C'est mon point fort.",
                "On fait le point demain.",
                "La cuisson à point.",
            ]),
            ("de-DE", [
                "Das ist ein wichtiger Punkt.",
                "Das Komma ist optional.",
                "Der Punkt ist, dass wir gehen.",
                "Wir treffen uns um Punkt acht.",
                "Das ist der springende Punkt.",
                "Ohne Komma geht es nicht.",
                "Zwei Komma fünf Prozent.",
                "Ein Fragezeichen bleibt.",
                "Setz einen Punkt dahinter.",
                "Das war ein guter Punkt.",
                "Der Doppelpunkt fehlt.",
                "Er hat ein Komma vergessen.",
            ]),
            ("it-IT", [
                "Il punto è questo.",
                "Un punto di vista diverso.",
                "La virgola è facoltativa.",
                "Ho fatto due punti.",
                "È un buon punto.",
                "Siamo al punto di partenza.",
                "Metti una virgola qui.",
                "Lo ha detto tra virgolette.",
                "Il trattino è corto.",
                "Facciamo il punto della situazione.",
            ]),
            ("pt-BR", [
                "O ponto de vista é claro.",
                "Esse é o ponto principal.",
                "A vírgula é opcional.",
                "Ganhamos por dois pontos.",
                "Esse é um bom ponto.",
                "Ele falou entre aspas.",
                "Coloque um hífen aqui.",
                "Estou no ponto de ônibus.",
                "Chegamos ao ponto final da viagem.",
                "Faltou uma vírgula.",
            ]),
        ]
        XCTAssertGreaterThanOrEqual(english.count, 60)
        for sentence in english {
            XCTAssertEqual(punctuated(sentence), sentence)
        }
        for (language, sentences) in others {
            for sentence in sentences {
                XCTAssertEqual(punctuated(sentence, language), sentence, language)
            }
        }
        // Numbers: a decimal or a time stays as said.
        XCTAssertEqual(punctuated("It costs two comma five million"), "It costs two comma five million")
        XCTAssertEqual(punctuated("The meeting is at 3 colon 30"), "The meeting is at 3 colon 30")
        XCTAssertEqual(punctuated("Tres coma cinco", "es-ES"), "Tres coma cinco")
        XCTAssertEqual(punctuated("Zwei Komma fünf Prozent", "de-DE"), "Zwei Komma fünf Prozent")
    }

    /// A closing name needs an open quote or bracket; a bare "quote" needs a closing one.
    func testQuotesAndBracketsPair() {
        XCTAssertEqual(punctuated("Close quote that"), "Close quote that")
        XCTAssertEqual(punctuated("He was fine close paren"), "He was fine close paren")
        XCTAssertEqual(punctuated("Can you quote me on that"), "Can you quote me on that")
        XCTAssertEqual(punctuated("He said \"hi end quote"), "He said \"hi\"", "a straight quote closes straight")
        XCTAssertEqual(punctuated("Lo dijo entre comillas", "es-ES"), "Lo dijo entre comillas")
    }

    func testOtherLanguagesStayAsSaid() {
        XCTAssertEqual(punctuated("Hallo komma", "nl-NL"), "Hallo komma")
        XCTAssertEqual(punctuated("你好逗号", "zh-CN"), "你好逗号")
    }

}
