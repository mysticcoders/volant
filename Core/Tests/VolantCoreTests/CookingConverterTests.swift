import XCTest
@testable import VolantCore

final class CookingConverterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale? = nil) -> [String?] {
        guard let answer = CookingConverter.evaluate(query, locale: locale ?? english) else { return [] }
        return [answer.result, answer.inputDetail, answer.resultDetail]
    }

    private func result(_ query: String) -> String? {
        CookingConverter.evaluate(query, locale: english)?.result
    }

    func testChartReferenceWeightsComeBackExactly() {
        XCTAssertEqual(result("1 cup all-purpose flour in g"), "120 g")
        XCTAssertEqual(result("1 cup bread flour in g"), "120 g")
        XCTAssertEqual(result("1 cup whole wheat flour in g"), "113 g")
        XCTAssertEqual(result("1 cup sugar in g"), "198 g")
        XCTAssertEqual(result("1 cup packed brown sugar in g"), "213 g")
        XCTAssertEqual(result("1 cup powdered sugar in g"), "113 g")
        XCTAssertEqual(result("1 stick butter in g"), "113 g")
        XCTAssertEqual(result("1 tbsp honey in g"), "21 g")
        XCTAssertEqual(result("1/2 cup maple syrup in g"), "156 g")
        XCTAssertEqual(result("1/2 cup cocoa in g"), "42 g")
        XCTAssertEqual(result("1 tbsp table salt in g"), "18 g")
        XCTAssertEqual(result("1 tsp baking powder in g"), "4 g")
        XCTAssertEqual(result("1/2 tsp baking soda in g"), "3 g")
        XCTAssertEqual(result("1 tbsp instant yeast in g"), "9 g")
        XCTAssertEqual(result("1 cup chocolate chips in g"), "170 g")
        XCTAssertEqual(result("1/4 cup olive oil in g"), "50 g")
    }

    func testCardsNameTheIngredientAndItsDensity() {
        XCTAssertEqual(card("1 cup flour in grams"), ["120 g", "All-purpose flour · 120 g per cup", "Approximate"])
        XCTAssertEqual(card("1 tsp salt in grams"), ["6 g", "Table salt · 18 g per tbsp", "Approximate"])
        XCTAssertEqual(card("1 cup water in grams"), ["237 g", "Water · 1 g per mL", "Approximate"])
        XCTAssertEqual(card("2 tbsp butter in g"), ["28.3 g", "Butter · 113 g per stick", "Approximate"])
    }

    func testWeightToVolumeGivesAKitchenMeasure() {
        XCTAssertEqual(card("250 g sugar in cups"), ["1.26 cups", "Granulated sugar · 198 g per cup", "About 1 ¼ cups"])
        XCTAssertEqual(card("100 g rice in cups").last, "About ½ cup")
        XCTAssertEqual(card("100 g butter in sticks").first, "0.885 sticks")
        XCTAssertEqual(card("10 g salt in tsp").last, "About 1 ¾ tsp")
        XCTAssertEqual(card("2 sticks butter in cups"), ["1 cup", "Butter · 113 g per stick", nil])
        XCTAssertEqual(card("500 g flour in ml").last, "Approximate")
    }

    func testOuncesAreWeightUnlessFluid() {
        XCTAssertEqual(result("1 cup honey in oz"), "11.9 oz")
        XCTAssertEqual(result("2 cups all-purpose flour in oz"), "8.47 oz")
        XCTAssertEqual(result("8 fl oz milk in g"), "227 g")
        XCTAssertEqual(result("1 lb butter in cups"), "2.01 cups")
    }

    func testRecipeAmountsAndPhrasings() {
        XCTAssertEqual(result("1 1/2 cups flour in g"), "180 g")
        XCTAssertEqual(result("½ cup butter in grams"), "113 g")
        XCTAssertEqual(result("1½ cups milk in grams"), "341 g")
        XCTAssertEqual(result("1 ½ cups milk in grams"), "341 g")
        XCTAssertEqual(result("a cup of brown sugar in grams"), "213 g")
        XCTAssertEqual(result("1 stick of butter in grams"), "113 g")
        XCTAssertEqual(result("1 stick in grams"), "113 g")
        XCTAssertEqual(result("1 cup sugar to grams"), "198 g")
        XCTAssertEqual(result("1 cup Confectioners' sugar in g"), "113 g")
        XCTAssertEqual(result("2 cups All-Purpose Flour in g"), "240 g")
        XCTAssertEqual(result("1 cup walnut in g"), nil)
        XCTAssertEqual(result("1 cup raisins in g"), "149 g")
        XCTAssertEqual(result("1,000 g flour in cups"), "8.33 cups")
        XCTAssertEqual(result("1 cup flour in kg"), "0.12 kg")
        XCTAssertEqual(result("1 cup flour in tbsp"), "16 tbsp")
    }

    func testMetricCupIs250Milliliters() {
        XCTAssertEqual(result("1 metric cup flour in grams"), "127 g")
        let plain = CalculationAnswer.answers(for: "1 metric cup in ml", locale: english)
        XCTAssertEqual(plain.map(\.result), ["250 mL"])
    }

    func testLocalesReadTheirOwnNumbers() {
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(card("1 000 g flour in cups", locale: french).first, "8,33 cups")
        XCTAssertEqual(card("1 1/2 cups flour in g", locale: french).first, "180 g")
        XCTAssertEqual(card("2,5 cups sugar in g", locale: Locale(identifier: "de_DE")).first, "495 g")
    }

    func testAmbiguousKosherSaltShowsBothBrands() {
        let answers = CookingConverter.evaluateAll("1 tbsp kosher salt in grams", locale: english)
        XCTAssertEqual(answers.map(\.result), ["8 g", "16 g"])
        XCTAssertEqual(answers.map(\.inputDetail), ["Kosher salt, Diamond Crystal · 8 g per tbsp", "Kosher salt, Morton · 16 g per tbsp"])
        XCTAssertEqual(result("1 tbsp morton kosher salt in g"), "16 g")
        XCTAssertEqual(result("1 tbsp diamond crystal in g"), "8 g")
    }

    func testUnknownIngredientsAndPlainUnitsGiveNoAnswer() {
        XCTAssertNil(result("1 cup coffee in ml"))
        XCTAssertNil(result("1 cup in grams"))
        XCTAssertNil(result("5 g in oz"))
        XCTAssertNil(result("2 tbsp in tsp"))
        XCTAssertNil(result("1 stick flour in grams"))
        XCTAssertNil(result("250 sugar in cups"))
        XCTAssertNil(result("0 cups flour in g"))
        XCTAssertNil(result("flour in grams"))
        XCTAssertNil(result("1 cup flour in km"))
    }

    func testGasMarks() {
        XCTAssertEqual(card("gas mark 4 in c"), ["177 °C", "Gas mark 4 = 350 °F", "Rounded to a whole degree"])
        XCTAssertEqual(card("gas mark 4 in f"), ["350 °F", nil, nil])
        XCTAssertEqual(result("gas mark 1/2 in c"), "121 °C")
        XCTAssertEqual(result("gas mark ¼ in f"), "225 °F")
        XCTAssertEqual(result("gas mark 10 in f"), "500 °F")
        XCTAssertEqual(card("350f in gas mark"), ["Gas mark 4", nil, "350 °F"])
        XCTAssertEqual(card("180 c in gas mark"), ["Gas mark 4", nil, "Nearest mark · 350 °F"])
        XCTAssertEqual(result("200°C in gas mark"), "Gas mark 6")
        XCTAssertEqual(result("250 degrees f in gas mark"), "Gas mark ½")
        XCTAssertNil(result("100 c in gas mark"))
        XCTAssertNil(result("gas mark 11 in c"))
        XCTAssertNil(result("gas mark 0 in c"))
    }

    func testSwapsParseBack() {
        for query in ["1 cup flour in grams", "250 g sugar in cups", "1 stick butter in g", "2 sticks butter in cups",
                      "1 metric cup flour in grams", "gas mark 4 in c", "350f in gas mark"] {
            guard let swap = CookingConverter.evaluate(query, locale: english)?.swapQuery else { return XCTFail(query) }
            XCTAssertNotNil(CookingConverter.evaluate(swap, locale: english), swap)
        }
        XCTAssertEqual(CookingConverter.evaluate("1 cup flour in grams", locale: english)?.swapQuery, "120 g all-purpose flour in cups")
        XCTAssertEqual(CookingConverter.evaluate("2 sticks butter in cups", locale: english)?.swapQuery, "1 cup butter in sticks")
        XCTAssertEqual(result("120 g all-purpose flour in cups"), "1 cup")
    }

    func testCalculatorShowsOneKitchenCard() {
        let answers = CalculationAnswer.answers(for: "1 cup flour in grams", locale: english)
        XCTAssertEqual(answers.map(\.result), ["120 g"])
        XCTAssertEqual(CalculationAnswer.answers(for: "what is 1 cup flour in grams?", locale: english).map(\.result), ["120 g"])
        XCTAssertEqual(CalculationAnswer.answers(for: "1 tbsp kosher salt in grams", locale: english).count, 2)
        XCTAssertEqual(CalculationAnswer.answers(for: "1 cup in ml", locale: english).map(\.result), ["236.588237 mL"])
    }
}
