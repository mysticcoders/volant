import XCTest

@testable import VolantCore



/// Settings › Dictation › Format lists. The English and Spanish inputs are what Apple Speech
/// (SpeechTranscriber, macOS 27.2, Samantha and Paulina voices) wrote for spoken lists.
final class SpokenListsTests: XCTestCase {
    private func lists(_ text: String, _ language: String = "en-US") -> String {
        SpokenLists.format(text, language: language)
    }

    func testNumberedListsInEnglish() {
        XCTAssertEqual(
            lists("Here is my shopping list. First, eggs. Second, milk, third, bread."),
            "Here is my shopping list.\n1. Eggs\n2. Milk\n3. Bread"
        )
        XCTAssertEqual(
            lists("My shopping list, 1st egg, 2nd milk, and 3rd bread."),
            "My shopping list:\n1. Egg\n2. Milk\n3. Bread"
        )
        XCTAssertEqual(
            lists("Number one, call the bank. Number two, pay rent. Number three, email Sam."),
            "1. Call the bank\n2. Pay rent\n3. Email Sam"
        )
        XCTAssertEqual(
            lists("One, buy tickets. Two, book the hotel. Three, pack."),
            "1. Buy tickets\n2. Book the hotel\n3. Pack"
        )
        XCTAssertEqual(
            lists("Step one preheat the oven, step two, mix the flour, step three, bake for 20 minutes."),
            "1. Preheat the oven\n2. Mix the flour\n3. Bake for 20 minutes"
        )
        XCTAssertEqual(lists("1. Eggs. 2. Milk."), "1. Eggs\n2. Milk")
        XCTAssertEqual(lists("First of all, thanks. Second of all, sorry."), "1. Thanks\n2. Sorry")
    }

    /// "finally" ends a list of two or more; what follows the last item's sentence is its own
    /// line, and a later list is found too.
    func testListEndsAndWhatFollows() {
        XCTAssertEqual(
            lists("First, preheat the oven. Second, mix. And finally, bake. Thanks!"),
            "1. Preheat the oven\n2. Mix\n3. Bake\nThanks!"
        )
        XCTAssertEqual(
            lists("Third, bake for 20 minutes. Let it cool. First, preheat. Second, mix."),
            "Third, bake for 20 minutes. Let it cool.\n1. Preheat\n2. Mix"
        )
        XCTAssertEqual(
            lists("Who's coming? First, Ana. Second, who else?"),
            "Who's coming?\n1. Ana\n2. Who else?"
        )
        XCTAssertEqual(
            lists("Packing: first, the iPhone charger, second, passport."),
            "Packing:\n1. The iPhone charger\n2. Passport"
        )
    }

    func testBulletsAndLineBreaks() {
        XCTAssertEqual(lists("Groceries, bullet, eggs, bullet, milk, bullet bread."), "Groceries:\n- Eggs\n- Milk\n- Bread")
        XCTAssertEqual(lists("Todo bullet ship it bullet tell Ravi"), "Todo:\n- Ship it\n- Tell Ravi")
        XCTAssertEqual(lists("Agenda: next item, budget. Next item, hiring."), "Agenda:\n- Budget\n- Hiring")
        XCTAssertEqual(lists("Dash, eggs. Dash, milk."), "- Eggs\n- Milk")
        XCTAssertEqual(
            lists("Dear Sam, new line, thanks for the help, new paragraph see you soon."),
            "Dear Sam\nthanks for the help\n\nsee you soon."
        )
        XCTAssertEqual(lists("Shopping new line bullet eggs new line bullet milk"), "Shopping\n- Eggs\n- Milk")
    }

    func testSpanish() {
        XCTAssertEqual(
            lists("Mi lista de compras. Primero, huevos, segundo, leche, tercero, pan.", "es-ES"),
            "Mi lista de compras.\n1. Huevos\n2. Leche\n3. Pan"
        )
        XCTAssertEqual(
            lists("Uno, Comprar boletos. Dos, reservar el hotel. Tres, hacer la maleta.", "es-MX"),
            "1. Comprar boletos\n2. Reservar el hotel\n3. Hacer la maleta"
        )
        XCTAssertEqual(lists("Viñeta, huevos, viñeta, leche, viñeta, pan.", "es-ES"), "- Huevos\n- Leche\n- Pan")
        XCTAssertEqual(
            lists("En primer lugar, gracias. En segundo lugar, perdón. Y por último, adiós.", "es-ES"),
            "1. Gracias\n2. Perdón\n3. Adiós"
        )
        XCTAssertEqual(
            lists("Hola Ana, nueva línea. Gracias por todo nuevo párrafo. Nos vemos.", "es-ES"),
            "Hola Ana\nGracias por todo\n\nNos vemos."
        )
        XCTAssertEqual(lists("Paso uno, lavar. Paso dos, secar.", "es-ES"), "1. Lavar\n2. Secar")
    }

    func testOtherLanguagesStayAsSaid() {
        XCTAssertEqual(lists("First, eggs. Second, milk.", "fr-FR"), "First, eggs. Second, milk.")
        XCTAssertEqual(lists("Erstens, Eier. Zweitens, Milch.", "de-DE"), "Erstens, Eier. Zweitens, Milch.")
    }

    /// Prose that only looks like a list stays exactly as it was heard.
    func testProseStaysAsSaid() {
        let english = [
            "The first time I saw it, I loved it.",
            "She is one of the best.",
            "I have two dogs and three cats.",
            "Don't second guess yourself.",
            "At first I didn't like it, but then I did.",
            "First things first, let's eat.",
            "He finished first and I finished second.",
            "One day we'll go there.",
            "Give me one second.",
            "It's the second time this week.",
            "We bought a new line of shoes.",
            "The bullet points are on the slide.",
            "I need to dash, see you.",
            "Number one fans only.",
            "One, two, three, go!",
            "Step by step, we got there.",
            "Who came first, the chicken or the egg?",
            "My first car was red and my second was blue.",
            "Two, maybe three people came.",
            "One more thing, call me later.",
            "The 1st time I saw it, I had to 2nd guess myself, one of the best, I have 2 dogs.",
            "First of all, thank you for coming.",
            "A bullet hit the wall.",
            "In the first place, it was not my fault.",
            "Add a new paragraph about pricing.",
            "Firstly, I disagree.",
            "We'll meet at 1, 2, or 3.",
            "Chapter one, two and three are done.",
            "One, two, buckle my shoe. Three, four, shut the door.",
            "He said one thing, then another.",
            "I was second in line, and first in my heart.",
            "The second half was better than the first.",
            "One of them said two words.",
            "First come, first served.",
            "Second to none.",
            "We'll do it in one, two weeks.",
            "Item one is missing.",
            "Point taken, next item please.",
            "Meet me at 1:30. 2 people are coming.",
            "That's a new line for me.",
            "Our new line of credit is ready.",
            "Third time's the charm.",
            "I came in second, and then first the next year.",
            "Last, but not least, thanks.",
            "One, I'm tired.",
            "First, let me say thanks for coming.",
            "Finally, we're done. Lastly, go home.",
            "The dash cam caught it.",
            "Number two pencils only.",
            "There are two options. One, we wait.",
        ]
        for sentence in english {
            XCTAssertEqual(lists(sentence), sentence)
        }
        let spanish = [
            "La primera vez que lo vi, me encantó.",
            "Es uno de los mejores.",
            "Tengo dos perros.",
            "Espera un segundo.",
            "Una nueva línea de productos.",
            "Primero llegó Ana y segundo llegó Luis.",
            "Uno nunca sabe.",
            "Vivo en el segundo piso.",
            "Compré una viñeta de Mafalda.",
            "Es mi primer día.",
            "Uno, dos, tres, ¡ya!",
            "En primer lugar estaba Ana.",
        ]
        for sentence in spanish {
            XCTAssertEqual(lists(sentence, "es-ES"), sentence)
        }
    }

    /// A counted microphone test is no list, in digits or still in words.
    func testCountsAreNoList() {
        for heard in [
            "Test 1, 2, 3.", "Test, 1, 2, 3.", "Test 1 2 3", "test one, two, three", "testing one two three",
            "counting one, two, three, four", "Counting 1, 2, 3, 4.", "1, 2, 3, testing.", "One, two, three, testing.",
        ] {
            XCTAssertEqual(lists(heard), heard)
        }
    }
}
