import CoreGraphics

/// Переводит увеличенную раскладку Dock в обычную по центрам иконок.
/// macOS увеличивает иконки по кривой вокруг указателя, поэтому равномерное растяжение сдвигает снег с иконок.
struct DockColumnMap {
    private let presented: [CGFloat]
    private let base: [CGFloat]
    private let body: ClosedRange<CGFloat>
    private let presentation: ClosedRange<CGFloat>

    /// nil, если раскладка покоя не совпадает с текущей по числу иконок.
    init?(body: ClosedRange<CGFloat>, presentation: ClosedRange<CGFloat>,
          restCenters: [CGFloat], presentedCenters: [CGFloat]) {
        guard !restCenters.isEmpty, restCenters.count == presentedCenters.count,
              body.upperBound > body.lowerBound, presentation.upperBound > presentation.lowerBound else { return nil }
        var presented = [presentation.lowerBound]
        var base = [body.lowerBound]
        for (rest, current) in zip(restCenters, presentedCenters).sorted(by: { $0.1 < $1.1 }) {
            // Узлы строго возрастают в обеих раскладках, иначе обратное отображение неоднозначно.
            guard current > presented.last!, rest > base.last!,
                  current < presentation.upperBound, rest < body.upperBound else { continue }
            presented.append(current)
            base.append(rest)
        }
        presented.append(presentation.upperBound)
        base.append(body.upperBound)
        self.presented = presented
        self.base = base
        self.body = body
        self.presentation = presentation
    }

    func base(atPresented x: CGFloat) -> CGFloat {
        guard x > presented[0] else { return base[0] }
        guard x < presented[presented.count - 1] else { return base[base.count - 1] }
        var high = 1
        while presented[high] < x { high += 1 }
        let low = high - 1
        let t = (x - presented[low]) / (presented[high] - presented[low])
        return base[low] + (base[high] - base[low]) * t
    }

    /// Пересобирает верх и подошву слоя на равномерной сетке увеличенного Dock.
    /// `values` хранит `count` вершин, затем `count` подошв, как в буфере SnowLayer.
    func resample(_ values: inout [Float], count: Int) {
        guard count > 1, values.count >= 2 * count else { return }
        let source = values
        let baseColumn = (body.upperBound - body.lowerBound) / CGFloat(count)
        let presentedColumn = (presentation.upperBound - presentation.lowerBound) / CGFloat(count)
        for i in 0..<count {
            let x = base(atPresented: presentation.lowerBound + (CGFloat(i) + 0.5) * presentedColumn)
            let position = min(max(Float((x - body.lowerBound) / baseColumn - 0.5), 0), Float(count - 1))
            let low = Int(position)
            let high = min(count - 1, low + 1)
            let t = position - Float(low)
            values[i] = source[low] + (source[high] - source[low]) * t
            values[count + i] = source[count + low] + (source[count + high] - source[count + low]) * t
        }
    }
}
