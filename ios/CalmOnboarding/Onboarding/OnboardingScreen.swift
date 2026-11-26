import SwiftUI
import UIKit

private enum AuthRoute: Hashable {
    case createAccount
    case signIn

    var title: String {
        switch self {
        case .createAccount: return "Создать аккаунт"
        case .signIn: return "Войти"
        }
    }
}

private struct OnboardingSlide {
    let title: String
    let description: String
    let hero: String
    let pagination: String
    let heroFrame: CGRect

    static let all: [OnboardingSlide] = [
        .init(
            title: "Отслеживайте\nсостояние",
            description: "Наблюдайте за результатами,\nотмечайте изменения и следите\nза динамикой на пути к восстановлению.",
            hero: "OnboardingHero1",
            pagination: "OnboardingPagination1",
            heroFrame: CGRect(x: 49, y: 108, width: 309.33, height: 303.33)
        ),
        .init(
            title: "Читайте\nрекоммендации",
            description: "Читайте полезные советы, находите\nновые идеи и выбирайте то, что\nактуально для вашего состояния.",
            hero: "OnboardingHero2",
            pagination: "OnboardingPagination2",
            heroFrame: CGRect(x: 58, y: 122, width: 285, height: 284)
        ),
        .init(
            title: "Улучшайте\nкачество сна",
            description: "Следите за режимом сна, настраивайте\nпривычки и постепенно выстраивайте\nкомфортный график.",
            hero: "OnboardingHero3",
            pagination: "OnboardingPagination3",
            heroFrame: CGRect(x: -11, y: 127, width: 424.67, height: 260.67)
        ),
        .init(
            title: "Сохраняйте\nлюбимое",
            description: "Добавляйте понравившиеся практики\nв избранное, чтобы быстро\nвозвращаться к ним в нужный момент.",
            hero: "OnboardingHero4",
            pagination: "OnboardingPagination4",
            heroFrame: CGRect(x: 20, y: 157, width: 348.67, height: 216)
        ),
    ]
}

private enum OnboardingPalette {
    static let ink = Color("TextPrimary")
    static let light = Color("TextLight")
    static let gradient = LinearGradient(
        stops: [
            .init(color: Color(red: 174 / 255.0, green: 164 / 255.0, blue: 238 / 255.0), location: 0.125),
            .init(color: Color(red: 240 / 255.0, green: 228 / 255.0, blue: 255 / 255.0), location: 0.809),
        ],
        startPoint: UnitPoint(x: 0.61, y: 0),
        endPoint: UnitPoint(x: 0.39, y: 1)
    )
}

private enum OnboardingFont {
    static func medium(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        // A licensed TT Commons file can be added later. The trial font is not
        // included because its license does not allow embedding in an iOS app.
        if UIFont(name: "TTCommonsClassicTrl-Md", size: size) != nil {
            return .custom("TTCommonsClassicTrl-Md", size: size, relativeTo: style)
        }
        return .system(size: size, weight: .medium)
    }
}

struct OnboardingScreen: View {
    @State private var selectedPage = 0
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $selectedPage) {
                ForEach(OnboardingSlide.all.indices, id: \.self) { index in
                    OnboardingSlideView(
                        slide: OnboardingSlide.all[index],
                        selectedPage: $selectedPage,
                        openAuth: { path.append($0) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AuthRoute.self) { route in
                AuthEntryView(title: route.title)
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    @Binding var selectedPage: Int
    let openAuth: (AuthRoute) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let origin = CGPoint(
                x: (geometry.size.width - 402 * scale) / 2,
                y: (geometry.size.height - 874 * scale) / 2
            )

            ZStack(alignment: .topLeading) {
                OnboardingPalette.gradient
                    .ignoresSafeArea()

                Image(slide.hero)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: slide.heroFrame.width * scale,
                        height: slide.heroFrame.height * scale
                    )
                    .position(
                        x: origin.x + slide.heroFrame.midX * scale,
                        y: origin.y + slide.heroFrame.midY * scale
                    )
                    .accessibilityHidden(true)

                Text(slide.title)
                    .font(OnboardingFont.medium(40 * scale, relativeTo: .largeTitle))
                    .tracking(-1 * scale)
                    .lineSpacing(-12 * scale)
                    .foregroundStyle(OnboardingPalette.ink)
                    .frame(width: 342 * scale, height: 68 * scale, alignment: .topLeading)
                    .position(x: origin.x + 201 * scale, y: origin.y + 506 * scale)

                Text(slide.description)
                    .font(OnboardingFont.medium(20 * scale, relativeTo: .body))
                    .lineSpacing(-2 * scale)
                    .foregroundStyle(OnboardingPalette.ink)
                    .frame(width: 342 * scale, height: 66 * scale, alignment: .topLeading)
                    .position(x: origin.x + 201 * scale, y: origin.y + 583 * scale)

                Image(slide.pagination)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 53 * scale, height: 8 * scale)
                    .overlay {
                        HStack(spacing: 0) {
                            ForEach(0..<OnboardingSlide.all.count, id: \.self) { index in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedPage = index
                                    }
                                } label: {
                                    Rectangle()
                                        .fill(.clear)
                                        .frame(width: 53 * scale / 4, height: 44 * scale)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Страница \(index + 1) из 4")
                            }
                        }
                    }
                    .position(x: origin.x + 201 * scale, y: origin.y + 656 * scale)

                actionButton("Создать аккаунт", dark: true, scale: scale) {
                    openAuth(.createAccount)
                }
                .position(x: origin.x + 201 * scale, y: origin.y + 707 * scale)

                actionButton("Войти", dark: false, scale: scale) {
                    openAuth(.signIn)
                }
                .position(x: origin.x + 201 * scale, y: origin.y + 781 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .contain)
    }

    private func actionButton(
        _ title: String,
        dark: Bool,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(OnboardingFont.medium(20 * scale, relativeTo: .headline))
                .foregroundStyle(dark ? OnboardingPalette.light : OnboardingPalette.ink)
                .frame(width: 342 * scale, height: 62 * scale)
                .background(dark ? OnboardingPalette.ink : OnboardingPalette.light)
                .clipShape(RoundedRectangle(cornerRadius: 32 * scale))
        }
        .buttonStyle(.plain)
    }
}
