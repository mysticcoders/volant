import XCTest

@testable import VolantCore

/// The SVG preview check (`ExtensionSVGPreview`): real logos from svgl and Simple Icons pass unchanged,
/// and a corpus of hostile markup, from entity expansion to external references and resource bombs, is
/// refused with the expected reason. Fixtures are text; nothing is parsed by an XML parser or drawn here.
final class ExtensionSVGPreviewTests: XCTestCase {
    private let open = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24">"#

    private func refusal(_ svg: String) -> ExtensionSVGPreview.Refusal? { ExtensionSVGPreview.check(Data(svg.utf8)) }

    /// Wraps `body` in an SVG root.
    private func wrapped(_ body: String) -> String { open + body + "</svg>" }

    func testRealLogosPassUnchanged() throws {
        for (name, svg) in SVGLogoFixtures.all {
            XCTAssertNil(refusal(svg), name)
            XCTAssertEqual(try ExtensionSVGPreview.sanitized(Data(svg.utf8)).get(), Data(svg.utf8), "\(name) is drawn as published, never rewritten")
        }
    }

    func testCommonBenignShapesPass() {
        let accepted = [
            #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n<!-- Generator: a design tool -->\n" + wrapped(#"<rect width="24" height="24" fill="red"/>"#),
            wrapped(#"<defs><linearGradient id="g"><stop offset="0" stop-color='#fff'/></linearGradient></defs><rect width="24" height="24" fill="url(#g)"/>"#),
            wrapped(#"<style><![CDATA[ .a { fill: url( '#g' ); } /* brand */ ]]></style><path class="a" d="M0 0h24v24H0z"/>"#),
            wrapped(#"<style>.a > .b { fill: #000 }</style><g class="a"><path class="b" d="M0 0h1v1z"/></g>"#),
            wrapped(#"<symbol id="s"><path d="M0 0h1v1z"/></symbol><use href='#s'/><use xlink:href='#s' x="4"/>"#),
            wrapped(#"<a href='#top'><text x="0" y="20">Fish &amp; Chips &#169; &#x2122;</text></a>"#),
            wrapped(#"<clipPath id="c"><circle r="4"/></clipPath><g clip-path="url(#c)" opacity=".5"><rect width="9" height="9"/></g>"#),
            "\u{FEFF}" + wrapped(#"<rect width="100%" height="1em"/>"#)
        ]
        for svg in accepted { XCTAssertNil(refusal(svg), svg) }
    }

    func testDeclarationsAndEntitiesAreRefused() {
        let billionLaughs = #"<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY a "lol"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>"#
            + wrapped("<text>&b;</text>")
        XCTAssertEqual(refusal(billionLaughs), .notSVG, "Copy detection already refuses a DOCTYPE with an internal subset")
        XCTAssertEqual(refusal(#"<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">"# + wrapped("")),
                       .declaration, "A DOCTYPE copy allows is still refused for drawing: it names an external DTD")
        XCTAssertEqual(refusal(#"<!DOCTYPE svg SYSTEM "file:///etc/passwd">"# + wrapped("")), .declaration, "XXE through an external DTD")
        XCTAssertEqual(refusal(wrapped(#"<!ENTITY xxe SYSTEM "file:///etc/passwd"><text>&xxe;</text>"#)), .declaration)
        XCTAssertEqual(refusal(wrapped("<text>&xxe;</text>")), .malformed, "An undeclared entity")
        XCTAssertEqual(refusal(wrapped(#"<rect fill="&nbsp;"/>"#)), .malformed)
        XCTAssertEqual(refusal(wrapped("<text>&#0;</text>")), .malformed)
        XCTAssertEqual(refusal(wrapped("<text>AT&T</text>")), .malformed, "A bare ampersand")
    }

    func testProcessingInstructionsOtherThanALeadingPrologAreRefused() {
        XCTAssertEqual(refusal(#"<?xml-stylesheet href="http://evil.example/a.css"?>"# + wrapped("")), .processingInstruction)
        XCTAssertEqual(refusal(#"<!-- first --><?xml version="1.0"?>"# + wrapped("")), .processingInstruction, "The prolog must come first")
        XCTAssertEqual(refusal(wrapped(#"<?php echo 1 ?>"#)), .processingInstruction)
    }

    func testScriptHTMLAndEmbeddedContentAreRefused() {
        let forbidden = [
            "<script>alert(1)</script>", #"<script href='#x'/>"#, "<SCRIPT>alert(1)</SCRIPT>", #"<svg:script>alert(1)</svg:script>"#,
            #"<foreignObject width="24" height="24"><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject>"#,
            #"<image href='#local' width="24" height="24"/>"#, #"<feImage href='#r'/>"#,
            "<iframe/>", "<object/>", "<embed/>", "<video/>", "<audio/>", "<canvas/>",
            #"<xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href='#a'/>"#,
            #"<set attributeName="href" to="http://evil.example/"/>"#, #"<animate attributeName="fill" values="red;blue"/>"#
        ]
        for body in forbidden { XCTAssertEqual(refusal(wrapped(body)), .forbiddenElement, body) }
    }

    func testEventAttributesAreRefused() {
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" onload="fetch('http://evil.example')"/>"#), .eventAttribute)
        XCTAssertEqual(refusal(wrapped(#"<rect ONCLICK="x()"/>"#)), .eventAttribute)
        XCTAssertEqual(refusal(wrapped(#"<rect ev:onmouseover="x()"/>"#)), .eventAttribute)
    }

    func testReferencesOutsideTheDocumentAreRefused() {
        let external = [
            #"<use href="http://127.0.0.1:8765/sprite.svg#a"/>"#, #"<use xlink:href="sprite.svg#a"/>"#, #"<use href=" https://evil.example/a.svg"/>"#,
            #"<a href="https://evil.example/"><path d="M0 0h1v1z"/></a>"#, #"<linearGradient id="g" xlink:href="file:///etc/passwd"/>"#,
            #"<use foo:href="//evil.example/a.svg"/>"#, #"<path src="https://evil.example/x" d="M0 0"/>"#, #"<g xml:base="https://evil.example/"/>"#,
            #"<rect fill="url(http://127.0.0.1:8765/fill.svg#g)"/>"#, #"<rect style="fill: URL( 'https://evil.example/p.svg#g' )"/>"#,
            #"<rect fill="url(data:image/svg+xml;base64,PHN2Zy8+)"/>"#, #"<rect fill="&#117;rl(http://evil.example/a)"/>"#,
            #"<style>rect { background: image-set("a.png" 1x) }</style>"#, #"<style>rect { fill: url(https://evil.example/p.svg#g) }</style>"#,
            #"<style><![CDATA[rect{mask:url(//evil.example/m.svg#m)}]]></style>"#, #"<style>rect { fill: u&#114;l(http://evil.example/a) }</style>"#
        ]
        for body in external { XCTAssertEqual(refusal(wrapped(body)), .externalReference, body) }
    }

    func testStylesThatImportFontsOrEscapesAreRefused() {
        let styles = [
            #"<style>@import url(#x);</style>"#, #"<style>@IMPORT "https://evil.example/a.css";</style>"#,
            #"<style>@font-face { font-family: x; src: local(Arial) }</style>"#, #"<style>rect { fill: u\72l(http://evil.example) }</style>"#,
            #"<style>@\69mport 'a.css';</style>"#, #"<rect style="fill:red/* never closed"/>"#, #"<style>/* brand */@import/**/'a.css';</style>"#
        ]
        for body in styles { XCTAssertEqual(refusal(wrapped(body)), .forbiddenStyle, body) }
        XCTAssertEqual(refusal(wrapped("<style><rect/></style>")), .malformed, "A style has no child elements")
    }

    func testFiltersAndMasksAreRefused() {
        let effects = [
            #"<filter id="f"><feGaussianBlur stdDeviation="2"/></filter>"#, "<feTurbulence/>", "<feFlood/>",
            #"<mask id="m"><rect width="9" height="9" fill="white"/></mask>"#, #"<rect filter="url(#f)"/>"#, #"<rect mask="url(#m)"/>"#,
            #"<rect style="filter: blur(4px)"/>"#, #"<rect style="-webkit-mask-image: none"/>"#, "<style>rect { filter: url(#f) }</style>",
            "<style><![CDATA[ .shadow { mask: url(#m) } ]]></style>"
        ]
        for body in effects { XCTAssertEqual(refusal(wrapped(body)), .expensiveEffect, body) }
        XCTAssertNil(refusal(wrapped(#"<rect id="mask0" class="filter"/>"#)), "Names in ids and classes are not effects")
    }

    func testUseThatMultipliesDrawingIsRefused() {
        var nested = #"<g id="g0"><rect width="1" height="1"/></g>"#
        for level in 1...9 { nested += #"<g id="g\#(level)">"# + String(repeating: #"<use href='#g\#(level - 1)'/>"#, count: 10) + "</g>" }
        XCTAssertEqual(refusal(wrapped("<defs>\(nested)</defs>" + #"<use href='#g9'/>"#)), .nestedUse, "A billion laughs made of <use>")
        XCTAssertEqual(refusal(wrapped(#"<g id="a"><use href='#a'/></g>"#)), .nestedUse, "A use inside what it draws")
        XCTAssertEqual(refusal(wrapped(#"<use id="u" href='#u'/>"#)), .nestedUse, "A use drawing itself")
        XCTAssertEqual(refusal(wrapped(#"<use id="u1" href='#s'/><use href='#u1'/><symbol id="s"><path d="M0 0"/></symbol>"#)), .nestedUse)
        XCTAssertNil(refusal(wrapped(#"<symbol id="s"><path d="M0 0"/></symbol>"# + String(repeating: #"<use href='#s'/>"#, count: 50))),
                     "Many uses of a plain symbol grow drawing only linearly")
    }

    func testResourceLimits() {
        XCTAssertEqual(refusal(wrapped(String(repeating: "<g/>", count: ExtensionSVGPreview.maximumElements))), .tooManyElements)
        XCTAssertNil(refusal(wrapped(String(repeating: "<g/>", count: ExtensionSVGPreview.maximumElements - 1))))
        let depth = ExtensionSVGPreview.maximumDepth
        XCTAssertEqual(refusal(wrapped(String(repeating: "<g>", count: depth) + String(repeating: "</g>", count: depth))), .tooDeep)
        XCTAssertNil(refusal(wrapped(String(repeating: "<g>", count: depth - 1) + String(repeating: "</g>", count: depth - 1))))
        let padding = String(repeating: " ", count: ExtensionSVGPreview.maximumBytes)
        XCTAssertEqual(refusal(wrapped("<!--\(padding)-->")), .tooLarge)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100000 100000"/>"#), .dimensionTooLarge)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-20000 0 10 10"/>"#), .dimensionTooLarge)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" width="16385" height="10"/>"#), .dimensionTooLarge)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" width="1e9" height="10"/>"#), .dimensionTooLarge)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" width="200in" height="10"/>"#), .dimensionTooLarge)
        XCTAssertEqual(refusal(wrapped(#"<pattern id="p" width="99999" height="1"/>"#)), .dimensionTooLarge, "Every element's size is bounded")
        XCTAssertNil(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" width="16384" height="16384" viewBox="0 0 16384 16384"/>"#))
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24"/>"#), .malformed)
        XCTAssertEqual(refusal(#"<svg xmlns="http://www.w3.org/2000/svg" width="NaN"/>"#), .malformed)
    }

    func testMalformedMarkupIsRefused() {
        let malformed = [
            open, open + "<g></svg>", open + "</g></svg>", wrapped("<rect width=24/>"), wrapped(#"<rect width="2"height="3"/>"#),
            wrapped(#"<rect fill="a<b"/>"#), wrapped(#"<rect fill="never closed/>"#), wrapped("<!-- never closed"), wrapped("<![CDATA[ never closed"),
            wrapped("") + "<svg/>", wrapped("") + "trailing text", wrapped("<é/>")
        ]
        for svg in malformed { XCTAssertEqual(refusal(svg), .malformed, svg) }
        XCTAssertEqual(refusal("<html><svg/></html>"), .notSVG)
        XCTAssertEqual(refusal("not markup"), .notSVG)
        XCTAssertEqual(ExtensionSVGPreview.check(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), .notSVG, "A PNG is not SVG")
    }

    func testDetectionMatchesCopy() {
        XCTAssertTrue(ExtensionSVGPreview.isSVG(Data(SVGLogoFixtures.vercelSVGL.utf8)))
        XCTAssertTrue(ExtensionSVGPreview.isSVG(Data(#"<!DOCTYPE svg><svg/>"#.utf8)), "Detection is copy's; drawing then refuses the DOCTYPE")
        XCTAssertEqual(ExtensionSVGPreview.check(Data(#"<!DOCTYPE svg><svg/>"#.utf8)), .declaration)
        XCTAssertFalse(ExtensionSVGPreview.isSVG(Data("<html></html>".utf8)))
    }
}
