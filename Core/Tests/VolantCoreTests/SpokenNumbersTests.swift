import XCTest

@testable import VolantCore

/// Spoken numbers written as digits; adapted from Hex's tests (see THIRD_PARTY_NOTICES.md).
final class SpokenNumbersTests: XCTestCase {
    func testSpokenNumbersBecomeDigits() {
        for (heard, written) in [
            ("Between five and ten minutes.", "Between 5 and 10 minutes."),
            ("Two or three days.", "2 or 3 days."),
            ("One to two hours.", "1 to 2 hours."),
            ("Meet at seven fifteen pm.", "Meet at 7:15 pm."),
            ("Seven oh five am.", "7:05 am."),
            ("At five o'clock.", "At 5 o'clock."),
            ("It's one mile away.", "It's 1 mile away."),
            ("It costs one dollar.", "It costs $1."),
            ("Five million dollars.", "$5 million."),
            ("Two thousand and five.", "2005."),
            ("May second.", "May 2nd."),
            ("On the first of may.", "On the 1st of may."),
            ("On September thirtieth.", "On September 30th."),
            ("Five point five dollars.", "$5.50."),
            ("Call five five five, one two three, four five six seven.", "Call 555-123-4567."),
            ("Built in nineteen oh five.", "Built in 1905."),
            ("It's minus one.", "It's -1."),
            ("Twenty-five people.", "25 people."),
            ("Two hundred people.", "200 people."),
            ("Three point five million.", "3.5 million."),
            ("Twenty one guns.", "21 guns."),
            ("Six feet.", "6 feet."),
            // "a hundred" or "a thousand" that a number goes on from; a decimal with two words after
            // "point"; percent ranges; both sides of "in", "out of", "to" and a height.
            ("A hundred and fifty people came.", "150 people came."),
            ("About a hundred and twenty.", "About 120."),
            ("It was a hundred and five degrees.", "It was 105 degrees."),
            ("I gave a hundred and ten percent.", "I gave 110%."),
            ("A thousand and one nights.", "1001 nights."),
            ("One point twenty one gigawatts.", "1.21 gigawatts."),
            ("Ten to fifteen percent.", "10 to 15%."),
            ("Five to ten percent.", "5 to 10%."),
            ("Fifty one percent.", "51%."),
            ("One in ten people.", "1 in 10 people."),
            ("Eight out of ten cats.", "8 out of 10 cats."),
            ("Nine times out of ten.", "9 times out of 10."),
            ("From zero to one hundred.", "From 0 to 100."),
            ("She is five foot six.", "She is 5 foot 6."),
            ("The code is oh four seven two.", "The code is 0472."),
            ("My zip is nine oh two one oh.", "My zip is 90210."),
            // Names keep converting where the number isn't capitalised, or is the last word.
            ("Area fifty one.", "Area 51."),
            ("Apollo thirteen.", "Apollo 13."),
            ("I shop at Forever Twenty One.", "I shop at Forever 21."),
            ("iPhone seventeen pro.", "iPhone 17 pro."),
            ("Windows eleven.", "Windows 11."),
            ("Twenty people came.", "20 people came."),
        ] {
            XCTAssertEqual(SpokenNumbers.digits(in: heard, language: "en-US"), written, heard)
        }
    }

    /// "one" alone, ordinals outside dates, fractions, and times, prices, ranges and scores
    /// without a marker or unit stay as said for now, as do digits and other languages.
    func testSpokenNumbersLeaveTheRestAsSaid() {
        for heard in [
            "One of them is broken.",
            "No one came to the meeting.",
            "That's the one I wanted.",
            "For once, it worked.",
            "To be honest, I won the game.",
            "I want to go too.",
            "Give me a second.",
            "We'll go through them one by one.",
            "We need one more chair.",
            "Use half a cup of sugar.",
            "Two thirds of the team agreed.",
            "I'll be there in one and a half hours.",
            "She finished first in the race.",
            "This is the third time I've asked.",
            "Let's meet at three thirty.",
            "The app is four ninety nine a month.",
            "Lunch was twelve fifty.",
            "The score was three to one.",
            "Kids aged eight to twelve can join.",
            "I ate breakfast at eight.",
            "We shipped build one thirty this morning.",
            "I work nine to five.",
            "The five point plan.",
            "Back in the nineteen nineties.",
            "Just my two cents.",
            "Ten to five.",
            "One or two people came.",
            "We sold 2,400 units.",
            "The app is $4.99 a month.",
            "Meet at 7:15.",
            "He lives on the twenty first floor.",
            "Have you tried GPT five yet?",
            "The deadline is march third.",
            "Two plus two equals four.",
            "Five, six, seven.",
            "Five five.",
            "It's a two-way street.",
            "Take a ten-minute break.",
            "Quarter past two.",
            "Twenty past six.",
            "Two of us went.",
            "Those two are fine.",
            "The train leaves at seven fifteen.",
            "Two dozen eggs.",
            "A hundred people.",
            // A number the engine capitalised as a name, mid-sentence or with a capital inside.
            "I love Twenty One Pilots.",
            "Use Eleven Labs for the voice.",
            "Ten Thousand Villages has nice gifts.",
            "I watched Fifty Shades of Grey.",
            "We saw Twelve Angry Men.",
            "I watch Sixty Minutes.",
            "Let's get Five Guys for lunch.",
            "We went to Six Flags.",
            // Arithmetic, "Oh", "a hundred" alone, and hundreds said short.
            "Ten minus five is five.",
            "Ten times two is twenty.",
            "Ten minus five.",
            // "one point" with a number after it is a decimal or nothing: never "one point 2".
            "At one point two people left.",
            "Oh one more thing.",
            "A hundred percent.",
            "It cost a hundred dollars.",
            "It's a couple hundred bucks.",
            "A few thousand people came.",
            "A million reasons.",
            "Half a million people.",
            "Two to three hundred people.",
            "One or two hundred people.",
        ] {
            XCTAssertEqual(SpokenNumbers.digits(in: heard, language: "en-US"), heard)
        }
        // Custom vocabulary and learned words stay as said, in any case.
        for (heard, term) in [
            ("let's get five guys for lunch", "Five Guys"),
            ("We love twenty one pilots.", "Twenty One Pilots"),
            ("I got a gift at ten thousand villages.", "Ten Thousand Villages"),
            ("I listen to nine inch nails.", "Nine Inch Nails"),
        ] {
            XCTAssertEqual(SpokenNumbers.digits(in: heard, language: "en-US", protectedTerms: [term]), heard, term)
        }
        XCTAssertEqual(SpokenNumbers.digits(in: "We love twenty one pilots.", language: "en-US"), "We love 21 pilots.")
        XCTAssertEqual(
            SpokenNumbers.digits(in: "Five guys ordered twenty five burgers.", language: "en-US", protectedTerms: ["Five Guys"]),
            "Five guys ordered 25 burgers."
        )
        XCTAssertEqual(SpokenNumbers.digits(in: "Cinco punto cinco.", language: "es-ES"), "Cinco punto cinco.")
        XCTAssertEqual(SpokenNumbers.digits(in: "The ratio is five point five.", language: "fr-FR"), "The ratio is five point five.")

    }
}
