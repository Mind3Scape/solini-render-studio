import SwiftUI
import SpriteKit

@main struct SaliniInsightLabApp: App {
    var body: some Scene {WindowGroup {InsightLabView()}}
}

struct InsightLabView: View {
    @StateObject private var driver=InsightDriver()
    @Environment(\.scenePhase) private var phase
    private let ink=Color(red:0.11,green:0.23,blue:0.24)
    var body: some View {
        GeometryReader { geometry in
            let compact=geometry.size.width<700
            VStack(spacing:0) {
                header
                ZStack(alignment:.topLeading) {
                    SpriteView(scene:driver.scene,preferredFramesPerSecond:60,options:[.ignoresSiblingOrder])
                        .accessibilityLabel("Производство. Анимированная платформа с изделиями")
                    VStack(alignment:.leading,spacing:10){
                        Text("ПРОИЗВОДСТВО · УЧАСТОК 04").font(.system(size:8,weight:.semibold)).tracking(1.3)
                        Text("Точность.\nВ каждом движении.").font(.system(size:compact ? 29:42,weight:.regular)).tracking(-1.4).lineSpacing(-2)
                        Text("Контроль качества → упаковка").font(.system(size:10)).foregroundStyle(ink.opacity(0.65))
                    }.padding(.leading,24).padding(.top,24).padding(.bottom,45)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .background(alignment:.top){LinearGradient(colors:[Color(red:0.94,green:0.95,blue:0.91).opacity(0.95),.clear],startPoint:.top,endPoint:.bottom).allowsHitTesting(false)}
                        .allowsHitTesting(false)
                    VStack(spacing:9){
                        Button{driver.zoom=min(1.15,driver.zoom+0.05)}label:{Image(systemName:"plus")}.accessibilityLabel("Приблизить").disabled(driver.zoom>=1.149)
                        Text("\(Int((driver.zoom*100).rounded()))%").font(.system(size:8,weight:.medium)).monospacedDigit().frame(width:34)
                        Button{driver.zoom=max(1,driver.zoom-0.05)}label:{Image(systemName:"minus")}.accessibilityLabel("Отдалить").disabled(driver.zoom<=1)
                    }.font(.system(size:12,weight:.medium)).padding(.vertical,12).background(.regularMaterial,in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.6),lineWidth:1)).padding(.top,25).padding(.trailing,18).frame(maxWidth:.infinity,alignment:.trailing)
                    if driver.onlyPlate {Text("Только исходное изображение").font(.system(size:10)).padding(.horizontal,13).padding(.vertical,9).background(.regularMaterial,in:Capsule()).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom).padding(.bottom,20)}
                }.clipped()
                board.padding(.horizontal,compact ? 16:30).padding(.top,17).padding(.bottom,8)
            }.background(Color(red:0.95,green:0.96,blue:0.94)).foregroundStyle(ink)
        }.preferredColorScheme(.light)
        .sheet(item:$driver.selected){zone in detail(zone).presentationDetents([.height(365)]).presentationDragIndicator(.visible)}
        .sheet(isPresented:$driver.layersOpen){layers.presentationDetents([.height(400)]).presentationDragIndicator(.visible)}
        .sheet(isPresented:$driver.infoOpen){information.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)}
        .onChange(of:phase){_,new in driver.isActive = new == .active}
    }
    private var header: some View {
        HStack(spacing:10){
            Image("salini-logo").resizable().scaledToFit().frame(width:83,height:34).accessibilityLabel("Salini")
            Rectangle().fill(ink.opacity(0.18)).frame(width:1,height:21).padding(.horizontal,3)
            Text("Insight").font(.system(size:20,weight:.light)).tracking(-0.8)
            Spacer()
            HStack(spacing:5){Circle().fill(Color(red:0.71,green:0.56,blue:0.28)).frame(width:4,height:4);Text("Проба 02").font(.system(size:9,weight:.medium))}.padding(.horizontal,10).padding(.vertical,8).background(.white.opacity(0.7),in:Capsule())
            Button{driver.infoOpen=true}label:{Image(systemName:"info.circle").font(.system(size:17,weight:.light))}.accessibilityLabel("О графическом прототипе")
        }.padding(.horizontal,22).padding(.bottom,15).padding(.top,8)
    }
    private var board: some View {
        VStack(alignment:.leading,spacing:15){
            HStack(alignment:.center){
                VStack(alignment:.leading,spacing:8){
                    HStack(spacing:6){Circle().fill(Color(red:0.33,green:0.55,blue:0.44)).frame(width:4,height:4);Text(["КОНТРОЛЬ КАЧЕСТВА","В ДВИЖЕНИИ","ПЕРЕДАЧА ИЗДЕЛИЙ"][driver.frame.stage]).font(.system(size:8,weight:.semibold)).tracking(1.2)}.foregroundStyle(ink.opacity(0.65))
                    Text(driver.frame.title).font(.system(size:21,weight:.medium)).tracking(-0.65).lineLimit(2).frame(height:50,alignment:.topLeading).contentTransition(.opacity)
                    Text("Партия 024 · 2 изделия · демонстрация").font(.system(size:9)).foregroundStyle(ink.opacity(0.5))
                }
                Spacer(minLength:5)
                Button{driver.follow.toggle()}label:{Image(systemName:driver.follow ? "scope":"map").font(.system(size:16,weight:.light)).frame(width:39,height:39).background(driver.follow ? ink:ink.opacity(0.08),in:Circle()).foregroundStyle(driver.follow ? .white:ink)}.accessibilityLabel(driver.follow ? "Перейти к обзору":"Следовать за партией")
            }
            HStack(spacing:12){
                stage(0,"Контроль","Поверхность",5)
                stage(1,"Движение","Защита изделий",13)
                stage(2,"Упаковка","Приём партии",23)
            }
            HStack(spacing:12){
                Button{driver.togglePlayback()}label:{Image(systemName:driver.playing ? "pause.fill":"play.fill").font(.system(size:12))}.accessibilityLabel(driver.playing ? "Приостановить":"Продолжить")
                Button{driver.seek(0);driver.playing=true}label:{Image(systemName:"arrow.counterclockwise").font(.system(size:12))}.accessibilityLabel("Начать сначала")
                Text(String(format:"00:%02d",Int(driver.time))).font(.system(size:9)).monospacedDigit().foregroundStyle(ink.opacity(0.5))
                Slider(value:Binding(get:{driver.time},set:{driver.seek($0)}),in:0...41.99).tint(ink.opacity(0.6)).accessibilityLabel("Время цикла")
                Button{driver.layersOpen=true}label:{Image(systemName:"square.3.layers.3d").font(.system(size:16,weight:.light))}.accessibilityLabel("Слои изображения")
            }.padding(.top,1)
            HStack{Text("ФИКСИРОВАННЫЙ РАКУРС");Spacer();Text("2.5D · ГРАФИЧЕСКИЙ ПРОТОТИП")}.font(.system(size:7,weight:.medium)).tracking(0.7).foregroundStyle(ink.opacity(0.4))
        }
    }
    private func stage(_ i:Int,_ title:String,_ subtitle:String,_ seek:Double)->some View {
        Button{driver.seek(seek);driver.selected = [LabZone.quality,.carrier,.packing][i]}label:{
            VStack(alignment:.leading,spacing:8){
                GeometryReader{g in ZStack(alignment:.leading){Rectangle().fill(ink.opacity(0.12));Rectangle().fill(ink.opacity(0.65)).frame(width:g.size.width*(driver.frame.stage>i ? 1:driver.frame.stage==i ? driver.frame.progress:0))}}.frame(height:1.5)
                HStack(spacing:5){Text("0\(i+1)").font(.system(size:8)).foregroundStyle(ink.opacity(0.4));Text(title).font(.system(size:10,weight:.medium))}
                Text(subtitle).font(.system(size:8)).foregroundStyle(ink.opacity(0.5))
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.buttonStyle(.plain)
    }
    private func detail(_ zone:LabZone)->some View {
        VStack(alignment:.leading,spacing:20){
            Text("SALINI INSIGHT · ДЕМО").font(.system(size:9,weight:.medium)).tracking(1.6).foregroundStyle(.secondary)
            Text(zone.rawValue).font(.system(size:32,weight:.regular)).tracking(-1)
            Text(zone == .carrier ? "Изделия и защитная форма перемещаются одним объектом. Поворот колёс рассчитывается по пройденному расстоянию; при остановке колёса тоже останавливаются.":zone == .packing ? "Платформа уходит на следующий участок за границей кадра и возвращается пустой. Разгрузка здесь не показана.":"Пост проверки поверхности и геометрии. Статус партии связан с движением на участке.").font(.system(size:14)).foregroundStyle(.secondary).lineSpacing(4)
            HStack{Text("Партия 024");Spacer();Text("2 изделия")}.font(.system(size:13,weight:.medium)).padding(.vertical,15).overlay(alignment:.top){Rectangle().fill(.secondary.opacity(0.15)).frame(height:0.5)}
            Button{driver.seek(zone == .quality ? 5:zone == .carrier ? 13:23);driver.selected=nil;driver.playing=true}label:{Text("Показать действие").font(.system(size:14,weight:.medium)).frame(maxWidth:.infinity).padding(15).background(ink,in:RoundedRectangle(cornerRadius:16)).foregroundStyle(.white)}
        }.padding(27).foregroundStyle(ink)
    }
    private var layers:some View {
        VStack(alignment:.leading,spacing:18){
            Text("Из изображения — в действие.").font(.system(size:27,weight:.regular)).tracking(-1)
            Toggle("Объект и груз",isOn:$driver.showCarrier)
            Toggle("Контактная тень",isOn:$driver.showShadows)
            Toggle("Колёса, свет, сканирование",isOn:$driver.showActivity)
            Toggle("Маршрут",isOn:$driver.showRoute)
            Button{driver.onlyPlate.toggle();driver.layersOpen=false}label:{Text(driver.onlyPlate ? "Вернуть живую сцену":"Показать только исходное изображение").font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity).padding(15).background(ink.opacity(0.08),in:RoundedRectangle(cornerRadius:14))}
            Text("Положение, перекрытия объектов и статусы вычисляются нативно в SpriteKit.").font(.system(size:11)).foregroundStyle(.secondary)
        }.font(.system(size:14)).tint(ink).padding(27)
    }
    private var information:some View {
        ScrollView {VStack(alignment:.leading,spacing:20){
            Text("ГРАФИЧЕСКИЙ ЭКСПЕРИМЕНТ").font(.system(size:9,weight:.medium)).tracking(1.6).foregroundStyle(.secondary)
            Text("Красота рендера.\nУправляемое действие.").font(.system(size:32,weight:.regular)).tracking(-1.2)
            Text("Окружение и состояния платформы созданы встроенной генерацией изображений OpenAI. Движение, тени, перекрытия, колёса и интерфейс — отдельные нативные слои.")
            Text("Сцена — художественная проба. Робот, процесс и изображения изделий не являются подтверждённой схемой производства или точной геометрией товаров Salini.")
            Text("В этой версии проверяем графику одной сцены. Ракурс закреплён, масштаб ограничен 115%. Анимация людей и разгрузка не входят в эту пробу.")
        }.font(.system(size:14)).foregroundStyle(ink).lineSpacing(4).padding(27)}
    }
}
