import Foundation
import CoreLocation

enum GeoService {

    // MARK: - Photon search (OpenStreetMap)
    static func search(_ query: String, near: CLLocationCoordinate2D?, limit: Int = 8) async -> [Place] {
        // Colloquial-friendly: try the raw query, then normalized/dialect variants.
        for variant in searchVariants(query) {
            let found = await photonSearch(variant, near: near, limit: limit)
            if !found.isEmpty { return found }
        }
        return []
    }

    static func normalizeArabic(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (a, b) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    static func searchVariants(_ query: String) -> [String] {
        var out: [String] = [query]
        let n = normalizeArabic(query)
        if n != query { out.append(n) }
        // dialect place words people actually say
        let swaps: [(String, String)] = [("جامع", "مسجد"), ("مسجد", "جامع"),
                                         ("بانزينخانه", "محطة وقود"), ("بنزينخانه", "محطة وقود"),
                                         ("بانزينخانة", "محطة وقود"), ("بنزينخانة", "محطة وقود"),
                                         ("كوفي", "مقهى"), ("فرن", "مخبز"), ("صيدليه", "صيدلية")]
        for (a, b) in swaps where n.contains(a) {
            out.append(n.replacingOccurrences(of: a, with: b))
        }
        return Array(NSOrderedSet(array: out)) as? [String] ?? out
    }

    private static func photonSearch(_ query: String, near: CLLocationCoordinate2D?, limit: Int) async -> [Place] {
        var comps = URLComponents(string: "https://photon.komoot.io/api/")!
        var items = [URLQueryItem(name: "q", value: query),
                     URLQueryItem(name: "limit", value: "\(limit)"),
                     URLQueryItem(name: "lang", value: "default")]
        if let near {
            items.append(URLQueryItem(name: "lat", value: "\(near.latitude)"))
            items.append(URLQueryItem(name: "lon", value: "\(near.longitude)"))
        }
        comps.queryItems = items
        guard let url = comps.url, let root = await getJSON(url) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        var results: [Place] = []
        for f in features {
            guard let geom = f["geometry"] as? [String: Any],
                  let coords = geom["coordinates"] as? [Double], coords.count == 2,
                  let props = f["properties"] as? [String: Any] else { continue }
            let name = (props["name"] as? String) ?? (props["street"] as? String) ?? "مكان"
            var addressParts: [String] = []
            if let street = props["street"] as? String, street != name { addressParts.append(street) }
            if let district = props["district"] as? String { addressParts.append(district) }
            if let city = props["city"] as? String { addressParts.append(city) }
            if let country = props["country"] as? String { addressParts.append(country) }
            results.append(Place.make(name: name,
                                      address: addressParts.joined(separator: "، "),
                                      lat: coords[1], lon: coords[0]))
        }
        var seen = Set<String>()
        let unique = results.filter { seen.insert($0.id).inserted }
        if let near {
            let origin = CLLocation(latitude: near.latitude, longitude: near.longitude)
            return unique.sorted {
                origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <
                origin.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
        }
        return unique
    }


    // MARK: - Reverse geocode (Nominatim)
    static func reverse(lat: Double, lon: Double) async -> Place? {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        comps.queryItems = [URLQueryItem(name: "format", value: "jsonv2"),
                            URLQueryItem(name: "lat", value: "\(lat)"),
                            URLQueryItem(name: "lon", value: "\(lon)"),
                            URLQueryItem(name: "accept-language", value: "ar"),
                            URLQueryItem(name: "zoom", value: "18")]
        guard let url = comps.url, let root = await getJSON(url) as? [String: Any] else { return nil }
        let name = (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (root["display_name"] as? String)?.split(separator: ",").first.map(String.init)
            ?? "موقع مُحدد"
        let address = (root["display_name"] as? String) ?? ""
        return Place.make(name: name, address: address, lat: lat, lon: lon)
    }

    /// Road/area name for the "current street" pill.
    static func currentStreet(lat: Double, lon: Double) async -> String? {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        comps.queryItems = [URLQueryItem(name: "format", value: "jsonv2"),
                            URLQueryItem(name: "lat", value: "\(lat)"),
                            URLQueryItem(name: "lon", value: "\(lon)"),
                            URLQueryItem(name: "accept-language", value: "ar"),
                            URLQueryItem(name: "addressdetails", value: "1"),
                            URLQueryItem(name: "zoom", value: "17")]
        guard let url = comps.url, let root = await getJSON(url) as? [String: Any],
              let addr = root["address"] as? [String: Any] else { return nil }
        for key in ["road", "pedestrian", "neighbourhood", "suburb", "village", "town"] {
            if let v = addr[key] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    // MARK: - Overpass nearby categories
    static func nearby(amenity: String, group: String, near: CLLocationCoordinate2D, radius: Double = 5000) async -> [Place] {
        // nwr = nodes + ways + relations: most hospitals/shops are drawn
        // as buildings (ways), not points. "out body center" gives each
        // way its centroid so it can be pinned.
        let query = """
        [out:json][timeout:20];
        nwr["\(group)"="\(amenity)"](around:\(Int(radius)),\(near.latitude),\(near.longitude));
        out body center 80;
        """
        let mirrors = ["https://overpass-api.de/api/interpreter",
                       "https://overpass.kumi.systems/api/interpreter",
                       "https://overpass.nchc.org.tw/api/interpreter"]
        var elements: [[String: Any]] = []
        for base in mirrors {
            var request = URLRequest(url: URL(string: base)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.setValue("Wijhati/1.6 iOS (id9871456@gmail.com)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("data=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")).data(using: .utf8)
            if let root = await sendJSON(request) as? [String: Any],
               let els = root["elements"] as? [[String: Any]], !els.isEmpty {
                elements = els
                break
            }
        }
        var results: [Place] = []
        for el in elements {
            let center = el["center"] as? [String: Any]
            guard let lat = (el["lat"] as? Double) ?? (center?["lat"] as? Double),
                  let lon = (el["lon"] as? Double) ?? (center?["lon"] as? Double),
                  let tags = el["tags"] as? [String: String] else { continue }
            let name = tags["name:ar"] ?? tags["name"] ?? tags["name:en"] ?? "مكان"
            var addr: [String] = []
            if let street = tags["addr:street"] { addr.append(street) }
            if let city = tags["addr:city"] { addr.append(city) }
            results.append(Place.make(name: name, address: addr.joined(separator: "، "),
                                      lat: lat, lon: lon,
                                      phone: tags["phone"] ?? tags["contact:phone"],
                                      website: tags["website"] ?? tags["contact:website"]))
        }
        let origin = CLLocation(latitude: near.latitude, longitude: near.longitude)
        return results.sorted {
            origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <
            origin.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    // MARK: - OSRM routing with waypoints
    static func route(from: CLLocationCoordinate2D, waypoints: [CLLocationCoordinate2D],
                      to: CLLocationCoordinate2D, profile: String) async -> [RouteData] {
        let all = [from] + waypoints + [to]
        let coords = all.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        // router.project-osrm.org silently returns CAR routes for every
        // profile, so use the FOSSGIS OSRM servers which run separate
        // car / bike / foot datasets.
        let host: String
        switch profile {
        case "foot": host = "https://routing.openstreetmap.de/routed-foot/route/v1/driving"
        case "bike": host = "https://routing.openstreetmap.de/routed-bike/route/v1/driving"
        default: host = "https://routing.openstreetmap.de/routed-car/route/v1/driving"
        }
        let query = "alternatives=true&steps=true&geometries=geojson&overview=full&continue_straight=false"
        let primary = await fetchRoutes(urlString: "\(host)/\(coords)?\(query)")
        if !primary.isEmpty { return saneDurations(primary, profile: profile) }
        if profile == "driving" {
            return await fetchRoutes(urlString: "https://router.project-osrm.org/route/v1/driving/\(coords)?\(query)")
        }
        return []
    }

    /// Safety net: if a server ever returns car-like times for walking or
    /// cycling (impossible average speed), recompute the duration from the
    /// route distance at a realistic speed for the mode.
    private static func saneDurations(_ routes: [RouteData], profile: String) -> [RouteData] {
        guard profile == "foot" || profile == "bike" else { return routes }
        let capKmh = profile == "foot" ? 9.0 : 32.0
        let cruiseKmh = profile == "foot" ? 5.0 : 16.0
        return routes.map { route in
            let kmh = route.distance / max(route.duration, 1) * 3.6
            guard kmh > capKmh else { return route }
            var fixed = route
            fixed.duration = route.distance / (cruiseKmh / 3.6)
            return fixed
        }
    }

    private static func fetchRoutes(urlString: String) async -> [RouteData] {
        guard let url = URL(string: urlString),
              let root = await getJSON(url) as? [String: Any],
              let routes = root["routes"] as? [[String: Any]] else { return [] }
        var out: [RouteData] = []
        for r in routes {
            guard let distance = r["distance"] as? Double,
                  let duration = r["duration"] as? Double,
                  let geometry = r["geometry"] as? [String: Any],
                  let coordsArr = geometry["coordinates"] as? [[Double]] else { continue }
            let coordinates = coordsArr.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            var steps: [StepData] = []
            if let legs = r["legs"] as? [[String: Any]] {
                for leg in legs {
                    guard let rawSteps = leg["steps"] as? [[String: Any]] else { continue }
                    for s in rawSteps {
                        let sd = (s["distance"] as? Double) ?? 0
                        let maneuver = (s["maneuver"] as? [String: Any]) ?? [:]
                        let loc = (maneuver["location"] as? [Double]) ?? [0, 0]
                        let coord = CLLocationCoordinate2D(latitude: loc.count > 1 ? loc[1] : 0,
                                                           longitude: loc.first ?? 0)
                        steps.append(StepData(instruction: arabicInstruction(maneuver: maneuver,
                                                                           name: (s["name"] as? String) ?? ""),
                                              distance: sd, coordinate: coord))
                    }
                }
            }
            out.append(RouteData(distance: distance, duration: duration,
                                 coordinates: coordinates, steps: steps))
        }
        return out.sorted { $0.duration < $1.duration }
    }

    // MARK: - Landmark-based navigation
    /// Rewrites turn instructions to mention a well-known place right at the
    /// turn ("انعطف يميناً، بجانب جامع النور") using one batched Overpass query.
    static func enrichRoutes(_ routes: [RouteData]) async -> [RouteData] {
        func isTurn(_ step: StepData) -> Bool {
            step.instruction.contains("يميناً") || step.instruction.contains("يساراً") ||
            step.instruction.contains("استدارة") || step.instruction.contains("الدوّار")
        }
        var points: [CLLocationCoordinate2D] = []
        for route in routes {
            for (idx, step) in route.steps.enumerated() where idx > 0 && idx < route.steps.count - 1 && isTurn(step) {
                points.append(step.coordinate)
            }
        }
        guard !points.isEmpty else { return routes }
        // Cap the batched query: a cross-country route can have 100+ turns
        // and Overpass would time out, losing every landmark.
        if points.count > 40 { points = Array(points.prefix(40)) }
        let clauses = points.map { p in
            "nwr[\"name\"][\"amenity\"~\"place_of_worship|pharmacy|hospital|school|fuel|marketplace|cafe|restaurant\"](around:80,\(p.latitude),\(p.longitude));"
        }.joined(separator: "\n")
        let query = "[out:json][timeout:20];(\n\(clauses)\n);out center 120;"
        var found: [(name: String, kind: String, coord: CLLocationCoordinate2D)] = []
        var lmRequest = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        lmRequest.httpMethod = "POST"
        lmRequest.timeoutInterval = 25
        lmRequest.setValue("Wijhati/1.14 iOS (id9871456@gmail.com)", forHTTPHeaderField: "User-Agent")
        lmRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        lmRequest.httpBody = ("data=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")).data(using: .utf8)
        if let root = await sendJSON(lmRequest) as? [String: Any],
           let elements = root["elements"] as? [[String: Any]] {
            for el in elements {
                guard let tags = el["tags"] as? [String: Any],
                      let name = tags["name"] as? String, !name.isEmpty else { continue }
                let lat = (el["lat"] as? Double) ?? ((el["center"] as? [String: Any])?["lat"] as? Double)
                let lon = (el["lon"] as? Double) ?? ((el["center"] as? [String: Any])?["lon"] as? Double)
                guard let lat, let lon else { continue }
                found.append((name, (tags["amenity"] as? String) ?? "", CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }
        }
        guard !found.isEmpty else { return routes }
        let kindWord: [String: String] = ["place_of_worship": "جامع", "pharmacy": "صيدلية",
                                          "hospital": "مستشفى", "school": "مدرسة",
                                          "fuel": "محطة وقود", "marketplace": "سوق"]
        var used = Set<String>()
        return routes.map { route in
            var copy = route
            copy.steps = route.steps.enumerated().map { idx, step in
                guard idx > 0, idx < route.steps.count - 1, isTurn(step) else { return step }
                let origin = CLLocation(latitude: step.coordinate.latitude, longitude: step.coordinate.longitude)
                let nearest = found
                    .filter { !used.contains($0.name) }
                    .map { (lm: $0, d: origin.distance(from: CLLocation(latitude: $0.coord.latitude, longitude: $0.coord.longitude))) }
                    .filter { $0.d <= 80 }
                    .sorted { $0.d < $1.d }
                    .first
                guard let hit = nearest else { return step }
                used.insert(hit.lm.name)
                var display = hit.lm.name
                if let word = kindWord[hit.lm.kind], !hit.lm.name.contains(word) {
                    display = "\(word) \(hit.lm.name)"
                }
                var stepCopy = step
                stepCopy.instruction = step.instruction + "، بجانب \(display)"
                return stepCopy
            }
            return copy
        }
    }

    static func arabicInstruction(maneuver: [String: Any], name: String) -> String {
        let type = (maneuver["type"] as? String) ?? ""
        let modifier = (maneuver["modifier"] as? String) ?? ""
        let exit = (maneuver["exit"] as? Int) ?? 0
        let dir: String
        switch modifier {
        case "left": dir = "يساراً"
        case "right": dir = "يميناً"
        case "slight left": dir = "قليلاً إلى اليسار"
        case "slight right": dir = "قليلاً إلى اليمين"
        case "sharp left": dir = "حاداً إلى اليسار"
        case "sharp right": dir = "حاداً إلى اليمين"
        case "uturn": dir = "للخلف (استدارة كاملة)"
        case "straight": dir = "مستقيماً"
        default: dir = ""
        }
        let onto = name.isEmpty ? "" : " إلى \(name)"
        switch type {
        case "depart": return "انطلق\(onto)"
        case "arrive": return "وصلت إلى وجهتك"
        case "turn": return dir.isEmpty ? "انعطف\(onto)" : "انعطف \(dir)\(onto)"
        case "new name", "continue": return "تابع \(dir)\(onto)".trimmingCharacters(in: .whitespaces)
        case "roundabout", "rotary": return "في الدوّار خذ المخرج رقم \(max(exit, 1))\(onto)"
        case "fork": return "عند المفترق اتجه \(dir)\(onto)"
        case "merge": return "اندمج \(dir)\(onto)"
        case "on ramp", "off ramp": return "خذ المنحدر \(dir)\(onto)"
        case "end of road": return "في نهاية الطريق انعطف \(dir)\(onto)"
        default: return dir.isEmpty ? "تابع السير\(onto)" : "اتجه \(dir)\(onto)"
        }
    }

    // MARK: - Open-Meteo weather + elevation
    struct WeatherNow {
        var temperature: Double
        var label: String
        var sunrise: String
        var sunset: String
    }

    static func weather(lat: Double, lon: Double) async -> WeatherNow? {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&daily=sunrise,sunset&timezone=auto&forecast_days=1"
        guard let root = await getJSON(URL(string: urlString)!) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int else { return nil }
        let daily = root["daily"] as? [String: Any]
        let sunrise = ((daily?["sunrise"] as? [String])?.first ?? "").suffix(5)
        let sunset = ((daily?["sunset"] as? [String])?.first ?? "").suffix(5)
        return WeatherNow(temperature: temp, label: weatherLabel(code),
                          sunrise: String(sunrise), sunset: String(sunset))
    }

    static func weatherLabel(_ code: Int) -> String {
        switch code {
        case 0: return "صافٍ"
        case 1, 2: return "غائم جزئياً"
        case 3: return "غائم"
        case 45, 48: return "ضباب"
        case 51, 53, 55: return "رذاذ"
        case 61, 63, 65, 80, 81, 82: return "مطر"
        case 66, 67: return "مطر متجمد"
        case 71, 73, 75, 77, 85, 86: return "ثلج"
        case 95, 96, 99: return "عاصفة رعدية"
        default: return "—"
        }
    }

    static func elevations(for coords: [CLLocationCoordinate2D]) async -> [Double] {
        guard !coords.isEmpty else { return [] }
        let step = max(1, coords.count / 30)
        var sample: [CLLocationCoordinate2D] = []
        for i in stride(from: 0, to: coords.count, by: step) { sample.append(coords[i]) }
        if let last = coords.last, sample.last?.latitude != last.latitude { sample.append(last) }
        let lats = sample.map { "\($0.latitude)" }.joined(separator: ",")
        let lons = sample.map { "\($0.longitude)" }.joined(separator: ",")
        guard let root = await getJSON(URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(lats)&longitude=\(lons)")!) as? [String: Any],
              let values = root["elevation"] as? [Double] else { return [] }
        return values
    }

    // MARK: - City search + speed limits

    struct CityResult: Identifiable {
        var id: String { name }
        var name: String
        var swLat: Double, swLon: Double, neLat: Double, neLon: Double
        var sw: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: swLat, longitude: swLon) }
        var ne: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: neLat, longitude: neLon) }
    }

    /// Cities with their Nominatim bounding boxes, for offline downloads.
    static func citySearch(_ query: String) async -> [CityResult] {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [URLQueryItem(name: "format", value: "jsonv2"),
                            URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "limit", value: "6"),
                            URLQueryItem(name: "accept-language", value: "ar")]
        guard let url = comps.url, let rows = await getJSON(url) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let display = row["display_name"] as? String,
                  let bb = row["boundingbox"] as? [String], bb.count == 4,
                  let minLat = Double(bb[0]), let maxLat = Double(bb[1]),
                  let minLon = Double(bb[2]), let maxLon = Double(bb[3]) else { return nil }
            let short = display.split(separator: ",").first.map(String.init) ?? display
            return CityResult(name: short, swLat: minLat, swLon: minLon, neLat: maxLat, neLon: maxLon)
        }
    }

    /// Posted speed limit (km/h) of the road nearest to a point, from
    /// OpenStreetMap's maxspeed tag. Nil when untagged (common in Iraq).
    static func speedLimit(near: CLLocationCoordinate2D) async -> Int? {
        let query = """
        [out:json][timeout:10];
        way(around:25,\(near.latitude),\(near.longitude))[highway][maxspeed];
        out tags 5;
        """
        let mirrors = ["https://overpass-api.de/api/interpreter",
                       "https://overpass.kumi.systems/api/interpreter",
                       "https://overpass.nchc.org.tw/api/interpreter"]
        for base in mirrors {
            var request = URLRequest(url: URL(string: base)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("Wijhati/1.42 iOS (id9871456@gmail.com)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("data=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")).data(using: .utf8)
            guard let root = await sendJSON(request) as? [String: Any],
                  let els = root["elements"] as? [[String: Any]] else { continue }
            for el in els {
                guard let raw = (el["tags"] as? [String: Any])?["maxspeed"] as? String else { continue }
                let lower = raw.lowercased()
                var digits = ""
                for ch in lower { if ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break } }
                guard let value = Int(digits), value > 0 else { continue }
                return lower.contains("mph") ? Int(Double(value) * 1.609) : value
            }
            return nil
        }
        return nil
    }

    // MARK: - Place details (contact, hours, photo)

    struct PlaceDetails {
        var phone: String?
        var website: String?
        var openingHours: String?
        var isOpenNow: Bool?
        var photoURL: URL?
    }

    /// Enriches a place card from the place's own OpenStreetMap record
    /// (Nominatim extratags) plus a matching Wikipedia photo.
    static func details(for place: Place) async -> PlaceDetails {
        var out = PlaceDetails(phone: place.phone, website: place.website)
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        comps.queryItems = [URLQueryItem(name: "format", value: "jsonv2"),
                            URLQueryItem(name: "lat", value: "\(place.latitude)"),
                            URLQueryItem(name: "lon", value: "\(place.longitude)"),
                            URLQueryItem(name: "accept-language", value: "ar"),
                            URLQueryItem(name: "extratags", value: "1"),
                            URLQueryItem(name: "zoom", value: "18")]
        var wikiTag: String?
        if let url = comps.url, let root = await getJSON(url) as? [String: Any],
           let tags = root["extratags"] as? [String: Any] {
            func tag(_ keys: [String]) -> String? {
                for k in keys { if let v = tags[k] as? String, !v.isEmpty { return v } }
                return nil
            }
            out.phone = out.phone ?? tag(["phone", "contact:phone", "contact:mobile"])
            out.website = out.website ?? tag(["website", "contact:website", "url"])
            out.openingHours = tag(["opening_hours"])
            wikiTag = tag(["wikipedia"])
        }
        if let hours = out.openingHours { out.isOpenNow = openNow(hours: hours, at: Date()) }
        out.photoURL = await wikipediaPhoto(place: place, tag: wikiTag)
        return out
    }

    private static func wikipediaPhoto(place: Place, tag: String?) async -> URL? {
        // 1) The place's own wikipedia tag, e.g. "ar:..." / "en:...".
        if let tag, let colon = tag.firstIndex(of: ":") {
            let lang = String(tag[tag.startIndex..<colon])
            let title = String(tag[tag.index(after: colon)...]).replacingOccurrences(of: " ", with: "_")
            if ["ar", "en"].contains(lang),
               let enc = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(enc)"),
               let root = await getJSON(url) as? [String: Any] {
                if let src = (root["originalimage"] as? [String: Any])?["source"] as? String { return URL(string: src) }
                if let src = (root["thumbnail"] as? [String: Any])?["source"] as? String { return URL(string: src) }
            }
        }
        // 2) Nearest Wikipedia article whose title shares a word with the name.
        let placeTokens = Set(normalizeArabic(place.name.lowercased()).split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !placeTokens.isEmpty else { return nil }
        for lang in ["ar", "en"] {
            var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
            comps.queryItems = [URLQueryItem(name: "action", value: "query"),
                                URLQueryItem(name: "format", value: "json"),
                                URLQueryItem(name: "generator", value: "geosearch"),
                                URLQueryItem(name: "ggscoord", value: "\(place.latitude)|\(place.longitude)"),
                                URLQueryItem(name: "ggsradius", value: "300"),
                                URLQueryItem(name: "ggslimit", value: "10"),
                                URLQueryItem(name: "prop", value: "pageimages"),
                                URLQueryItem(name: "piprop", value: "original")]
            guard let url = comps.url, let root = await getJSON(url) as? [String: Any],
                  let pages = (root["query"] as? [String: Any])?["pages"] as? [String: Any] else { continue }
            for page in pages.values {
                guard let p = page as? [String: Any], let title = p["title"] as? String,
                      let src = (p["original"] as? [String: Any])?["source"] as? String else { continue }
                let titleTokens = Set(normalizeArabic(title.lowercased()).split(separator: " ").map(String.init))
                if !placeTokens.isDisjoint(with: titleTokens) { return URL(string: src) }
            }
        }
        return nil
    }

    /// Best-effort evaluator for common opening_hours shapes ("24/7",
    /// "Mo-Fr 08:00-17:00", "Sa-Th 09:00-23:00; Fr off"). Nil = too exotic.
    static func openNow(hours: String, at date: Date) -> Bool? {
        let text = hours.trimmingCharacters(in: .whitespaces)
        if text == "24/7" { return true }
        let order = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let calNum = ["Mo": 2, "Tu": 3, "We": 4, "Th": 5, "Fr": 6, "Sa": 7, "Su": 1]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let weekday = cal.component(.weekday, from: date)
        let nowMin = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        func expandDays(_ spec: String) -> Set<Int>? {
            var days = Set<Int>()
            for part in spec.split(separator: ",") {
                let p = String(part)
                if p.contains("-") {
                    let ab = p.split(separator: "-").map(String.init)
                    guard ab.count == 2, let i1 = order.firstIndex(of: ab[0]), let i2 = order.firstIndex(of: ab[1]) else { return nil }
                    var i = i1
                    while true { days.insert(calNum[order[i]]!); if i == i2 { break }; i = (i + 1) % 7 }
                } else {
                    guard let n = calNum[p] else { return nil }
                    days.insert(n)
                }
            }
            return days
        }
        func minutes(_ t: String) -> Int? {
            let ab = t.split(separator: ":")
            guard ab.count == 2, let h = Int(ab[0]), let m = Int(ab[1]), h <= 24, m < 60 else { return nil }
            return h * 60 + m
        }
        var sawRule = false
        var sawToday = false
        for rawRule in text.split(separator: ";") {
            let words = rawRule.split(separator: " ").map(String.init)
            guard !words.isEmpty else { continue }
            var daySpec: String? = nil
            var ranges: [(Int, Int)] = []
            var off = false
            var ok = true
            for w in words {
                if w == "off" { off = true; continue }
                if w.contains(":") {
                    let ab = w.split(separator: "-")
                    guard ab.count == 2, let a = minutes(String(ab[0])), let b = minutes(String(ab[1])) else { ok = false; break }
                    ranges.append((a, b))
                    continue
                }
                // A word of day codes / ranges / comma lists.
                let cleaned = w.trimmingCharacters(in: CharacterSet(charactersIn: ","))
                if cleaned.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "," }) && expandDays(w) != nil {
                    daySpec = w
                    continue
                }
                ok = false; break
            }
            guard ok else { continue }
            sawRule = true
            let days = daySpec.flatMap { expandDays($0) } ?? Set(1...7)
            // Overnight spill from yesterday.
            let yesterday = weekday == 1 ? 7 : weekday - 1
            if days.contains(yesterday) {
                for (a, b) in ranges where b < a && nowMin < b { return true }
            }
            guard days.contains(weekday) else { continue }
            sawToday = true
            if off { continue }
            if ranges.isEmpty { return true } // day named with no times = open all day
            for (a, b) in ranges {
                if b > a { if nowMin >= a && nowMin < b { return true } }
                else if nowMin >= a { return true }
            }
        }
        if sawToday { return false }
        return sawRule ? false : nil
    }

    // MARK: - HTTP helpers
    static func getJSON(_ url: URL) async -> Any? {
        // A real User-Agent + a sane timeout: Nominatim/Photon ask for an
        // identifying UA, and the shared session's 60 s default can leave
        // the UI hanging on a dead connection.
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Wijhati/1.34 iOS (id9871456@gmail.com)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONSerialization.jsonObject(with: data)
        } catch { return nil }
    }
    static func sendJSON(_ request: URLRequest) async -> Any? {
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONSerialization.jsonObject(with: data)
        } catch { return nil }
    }
}
