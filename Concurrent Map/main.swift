import Foundation

struct Point {
    let lat: Double
    let lon: Double
    let ele: Double
}

final class Parser: NSObject, XMLParserDelegate {
    var inTrk = false

    var points: [Point] = []
    var pending: (lat: Double, lon: Double)?
    var elementContents: String = ""
    var name = ""

    init?(url: URL) {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        super.init()
        parser.delegate = self
        guard parser.parse() else { return nil }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        elementContents += string
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard inTrk else {
            inTrk = elementName == "trk"
            return
        }
        if elementName == "trkpt" {
            guard let latStr = attributeDict["lat"], let lat = Double(latStr),
                let lonStr = attributeDict["lon"], let lon = Double(lonStr) else { return }
            pending = (lat: lat, lon: lon)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { elementContents = "" }
        var trimmed: String { return elementContents.trimmingCharacters(in: .whitespacesAndNewlines) }
        if elementName == "trk" {
            inTrk = false
        } else if elementName == "ele" {
            guard let p = pending, let ele = Double(trimmed) else { return }
            points.append(Point(lat: p.lat, lon: p.lon, ele: ele))
        } else if elementName == "name" && inTrk {
            name = trimmed
        }
    }
}

@discardableResult func time<Result>(name: StaticString = #function, line: Int = #line, _ f: () -> Result) -> Result {
    let startTime = DispatchTime.now()
    let result = f()
    let endTime = DispatchTime.now()
    let diff = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000 as Double
    print("\(name) (line \(line)): \(diff) sec")
    return result
}

let base = "/Users/chris/Dropbox (eidhof.nl)/swift talk/to-be-finished/Concurrency/gpx/"
let currentDirectory = try! FileManager.default.contentsOfDirectory(atPath: base)

let urls = currentDirectory.filter { $0.hasSuffix(".gpx") }.map { URL(fileURLWithPath: base).appendingPathComponent($0)}

final class ThreadSafe<A> {
    private var _value: A
    private let queue = DispatchQueue(label: "ThreadSafe")
    init(_ value: A) {
        self._value = value
    }
    
    var value: A {
        return queue.sync { _value }
    }
    
    func atomically(_ transform: (inout A) -> ()) {
        queue.sync {
            transform(&self._value)
        }
    }
}

extension Array {
    func concurrentMap<B>(_ transform: @escaping (Element) -> B) -> [B] {
        let result = ThreadSafe(Array<B?>(repeating: nil, count: urls.count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            let transformed = transform(element)
            result.atomically {
                $0[idx] = transformed
            }
        }
        return result.value.map { $0! }

    }
}

time {
    let result = urls.concurrentMap { Parser(url: $0)!.points.count }
    print(result.reduce(0, +))
}
