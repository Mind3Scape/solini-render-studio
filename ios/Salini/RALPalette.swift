import UIKit

/// A selection of RAL Classic codes with commonly published sRGB screen approximations.
/// Salini states 216 colours of its RAL Classic palette; availability of a shade for a given
/// material and finish is confirmed by a manager. Screen colours are approximations only.
struct RALColour: Hashable {
  let code: String
  let name: String
  let hex: UInt
  var colour: UIColor { UIColor(hex: hex) }
}

enum RALPalette {
  static let colours: [RALColour] = [
    RALColour(code: "9016", name: "Транспортный белый", hex: 0xF1F0EA),
    RALColour(code: "9010", name: "Чистый белый", hex: 0xF1ECE1),
    RALColour(code: "9003", name: "Сигнальный белый", hex: 0xECECE7),
    RALColour(code: "9001", name: "Кремово-белый", hex: 0xE9E0D2),
    RALColour(code: "1013", name: "Жемчужно-белый", hex: 0xE3D9C6),
    RALColour(code: "1015", name: "Светлая слоновая кость", hex: 0xE6D2B5),
    RALColour(code: "1001", name: "Бежевый", hex: 0xD0B084),
    RALColour(code: "1019", name: "Серо-бежевый", hex: 0xA48F7A),
    RALColour(code: "9002", name: "Серо-белый", hex: 0xD7D5CB),
    RALColour(code: "7035", name: "Светло-серый", hex: 0xCBD0CC),
    RALColour(code: "7044", name: "Шёлковисто-серый", hex: 0xB7B3A8),
    RALColour(code: "7004", name: "Сигнальный серый", hex: 0x9C9C9C),
    RALColour(code: "7037", name: "Пыльно-серый", hex: 0x7A7B7A),
    RALColour(code: "7016", name: "Антрацитово-серый", hex: 0x383E42),
    RALColour(code: "7021", name: "Чёрно-серый", hex: 0x2F3234),
    RALColour(code: "9011", name: "Графитовый чёрный", hex: 0x1C1E20),
    RALColour(code: "9005", name: "Глубокий чёрный", hex: 0x0E0E10),
    RALColour(code: "8017", name: "Шоколадно-коричневый", hex: 0x45302B),
    RALColour(code: "3005", name: "Винно-красный", hex: 0x59191F),
    RALColour(code: "3012", name: "Бежево-красный", hex: 0xC6846D),
    RALColour(code: "3015", name: "Светло-розовый", hex: 0xD8A0A6),
    RALColour(code: "6019", name: "Бело-зелёный", hex: 0xB9CEAC),
    RALColour(code: "6021", name: "Бледно-зелёный", hex: 0x89AC76),
    RALColour(code: "6011", name: "Резедово-зелёный", hex: 0x68825B),
    RALColour(code: "6005", name: "Зелёный мох", hex: 0x114232),
    RALColour(code: "6034", name: "Пастельно-бирюзовый", hex: 0x7AADAC),
    RALColour(code: "5024", name: "Пастельно-синий", hex: 0x6093AC),
    RALColour(code: "5014", name: "Голубино-синий", hex: 0x637D96),
    RALColour(code: "5003", name: "Сапфирово-синий", hex: 0x1F3855),
    RALColour(code: "5011", name: "Стальной синий", hex: 0x1A2B3C),
  ]
  static func colour(_ code: String) -> RALColour? { colours.first { $0.code == code } }
}
