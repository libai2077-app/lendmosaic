import SwiftUI
struct ProductRoot:View {
    @Environment(\.launchIsCovering) private var launchIsCovering
 @State private var model=LendModel();@AppStorage("language") private var language="system";@AppStorage("appearance") private var appearance="system"
 var body:some View{TabView{
 NavigationStack{LendHome(model:model)}.tabItem{Label{Words("On loan")}icon:{Image(systemName:"arrow.up.right.circle")}}
 NavigationStack{LendHistory(model:model)}.tabItem{Label{Words("Returns")}icon:{Image(systemName:"clock.arrow.circlepath")}}
 NavigationStack{SettingsView(appName:"LendMosaic",canSeed:model.records.isEmpty,seed:{model.seed()},export:{try model.repository.encoded()})}.tabItem{Label{Words("Settings")}icon:{Image(systemName:"gearshape")}}
 }.tint(Design.accent).environment(\.locale,Locale(identifier:Languages.resolve(language))).preferredColorScheme(appearance=="system" ? nil:appearance=="dark" ? .dark:.light).task{if ProcessInfo.processInfo.arguments.contains("--demo-data"){model.seed()}}
 .alert(Text(LocalizedStringKey(model.repository.error ?? "Error")),isPresented:Binding(get:{model.repository.error != nil && !launchIsCovering},set:{if !$0{model.repository.error=nil}})){Button("Done",role:.cancel){}}
 }
}
struct LoanRow:View {let loan:Loan;var body:some View{HStack(alignment:.top,spacing:16){VStack(spacing:5){Image(systemName:loan.returned == nil ? "arrow.up.right":"checkmark").font(.headline).foregroundStyle(Design.accent);Rectangle().fill(Design.accent.opacity(0.25)).frame(width:2,height:42)}.accessibilityHidden(true);VStack(alignment:.leading,spacing:8){Text(verbatim:loan.name).font(.headline);Text(verbatim:loan.borrower).foregroundStyle(Design.secondary);HStack{Words(loan.status()).font(.caption.weight(.semibold)).foregroundStyle(Design.accent);Spacer();Text(verbatim:dateText(loan.returned ?? loan.due)).font(.caption).foregroundStyle(Design.secondary)}}}.padding(.vertical,10)}}
struct LendHome:View {
 let model:LendModel;@State private var query="";@State private var adding=false
 var filtered:[Loan]{model.active.filter{query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.borrower.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)}}
 var body:some View{List{
 Section{VStack(alignment:.leading,spacing:18){SectionHeading(title:"Keep track. Give freely.",subtitle:"Know what is out, and when it comes home.");HStack{Metric(title:"On loan",value:number(Double(model.active.count),digits:0));Metric(title:"Overdue",value:number(Double(model.active.filter{$0.days()<0}.count),digits:0))}}.padding(.vertical,12)}.listRowBackground(Color.clear)
 if filtered.isEmpty{EmptyRecords(search:!query.isEmpty).listRowBackground(Color.clear)}
 ForEach([true,false],id:\.self){overdue in let group=filtered.filter{($0.days()<0)==overdue};if !group.isEmpty{Section{ForEach(group){loan in NavigationLink{LendDetail(model:model,id:loan.id)}label:{LoanRow(loan:loan)}}}header:{Words(overdue ? "Overdue":"Upcoming").foregroundStyle(Design.secondary)}}}
 }.scrollContentBackground(.hidden).background(AppBackground()).navigationTitle(Text(LocalizedStringKey("On loan"))).searchable(text:$query,prompt:Text(LocalizedStringKey("Search"))).toolbar{Button{adding=true}label:{Image(systemName:"plus")}.accessibilityLabel(Text(LocalizedStringKey("Add"))).accessibilityIdentifier("addRecord")}.sheet(isPresented:$adding){LendEditor(model:model,loan:Loan())}}
}
struct LendDetail:View {
 let model:LendModel;let id:UUID;@State private var editing=false;@State private var deleting=false;@State private var confirmingReturn=false;@Environment(\.dismiss) private var dismiss
 var loan:Loan?{model.records.first{$0.id==id}}
 var body:some View{Group{if let p=loan{List{
 Section{Text(verbatim:p.name).font(.title2.bold());Words(p.status()).foregroundStyle(Design.accent);LabeledContent{Text(verbatim:p.borrower).foregroundStyle(Design.secondary)}label:{Words("Borrower")};LabeledContent{Text(verbatim:p.category).foregroundStyle(Design.secondary)}label:{Words("Category")}}
 Section{LabeledContent{Text(verbatim:dateText(p.lent)).foregroundStyle(Design.secondary)}label:{Words("Lent on")};LabeledContent{Text(verbatim:dateText(p.due)).foregroundStyle(Design.secondary)}label:{Words("Due date")};if let returned=p.returned{LabeledContent{Text(verbatim:dateText(returned)).foregroundStyle(Design.secondary)}label:{Words("Returned on")}}}
 Section{if p.returned==nil{Button{confirmingReturn=true}label:{Label{Words("Mark returned")}icon:{Image(systemName:"checkmark.circle")}}.accessibilityIdentifier("returnItem")}else{Button{_ = model.reopen(id)}label:{Words("Undo return")}.accessibilityIdentifier("undoReturn")};NavigationLink{LoanTimeline(loan:p)}label:{Label{Words("Loan timeline")}icon:{Image(systemName:"point.topleft.down.curvedto.point.bottomright.up")}}.accessibilityIdentifier("resultLink")}
 NotesBlock(text:p.notes)
 Section{Button(role:.destructive){deleting=true}label:{Words("Delete")}.accessibilityIdentifier("deleteRecord")}
 }.sheet(isPresented:$editing){LendEditor(model:model,loan:p)}}else{EmptyRecords()}}.scrollContentBackground(.hidden).background(AppBackground()).navigationTitle(Text(LocalizedStringKey("Loan details"))).navigationBarTitleDisplayMode(.inline).toolbar{Button{editing=true}label:{Words("Edit")}.accessibilityIdentifier("editRecord")}.confirmationDialog(Text(LocalizedStringKey("Delete this record?")),isPresented:$deleting,titleVisibility:.visible){Button("Delete",role:.destructive){if let p=loan{model.delete(p);if model.repository.error==nil{dismiss()}}}}.confirmationDialog(Text(LocalizedStringKey("Confirm this item is back with you.")),isPresented:$confirmingReturn,titleVisibility:.visible){Button("Mark returned"){_ = model.returnItem(id)}}}
}
struct LoanTimeline:View {
 let loan:Loan
 var body:some View{ScrollView{VStack(alignment:.leading,spacing:28){SectionHeading(title:"Loan timeline",subtitle:"A record of this item's journey.");Text(verbatim:loan.name).font(.title2.bold());event("Lent on",loan.lent,"arrow.up.right.circle");event("Due date",loan.due,"calendar");if let returned=loan.returned{event("Returned on",returned,"checkmark.circle.fill")}else{Divider();Words(loan.status()).font(.title);Metric(title:"Days until due",value:number(Double(loan.days()),digits:0))};Words("Dates are records only. No reminders or messages are sent.").font(.footnote).foregroundStyle(Design.secondary)}.padding(28)}.background(AppBackground()).navigationTitle(Text(LocalizedStringKey("Loan timeline"))).navigationBarTitleDisplayMode(.inline)}
 func event(_ title:String,_ date:Date,_ icon:String)->some View{HStack(alignment:.top,spacing:20){Image(systemName:icon).font(.title).foregroundStyle(Design.accent);VStack(alignment:.leading,spacing:8){Words(title).font(.headline);Text(verbatim:dateText(date)).font(.title3)}}}
}
struct LendHistory:View {let model:LendModel;var body:some View{List{Section{HStack{Metric(title:"Returned",value:number(Double(model.history.count),digits:0));Metric(title:"On loan",value:number(Double(model.active.count),digits:0))}};if model.history.isEmpty{EmptyRecords()};ForEach(model.history){p in NavigationLink{LendDetail(model:model,id:p.id)}label:{LoanRow(loan:p)}}}.scrollContentBackground(.hidden).background(AppBackground()).navigationTitle(Text(LocalizedStringKey("Returns")))}}
struct LendEditor:View {
 let model:LendModel;@State var loan:Loan;@State private var invalid=false;@Environment(\.dismiss) private var dismiss
 var body:some View{NavigationStack{Form{
 if invalid{Words("Enter item, borrower and category. Dates must follow the lending date.").foregroundStyle(Design.danger).accessibilityIdentifier("validationError")}
 Section{Field(key:"Name",value:$loan.name,identifier:"nameField");Field(key:"Borrower",value:$loan.borrower,identifier:"borrowerField");Field(key:"Category",value:$loan.category,identifier:"categoryField")}
 Section{DatePicker(selection:$loan.lent,in:...Date(),displayedComponents:.date){Words("Lent on")};DatePicker(selection:$loan.due,displayedComponents:.date){Words("Due date")};if loan.returned != nil{DatePicker(selection:Binding(get:{loan.returned ?? Date()},set:{loan.returned=$0}),displayedComponents:.date){Words("Returned on")}}}
 Section{Field(key:"Notes",value:$loan.notes)}
 }.scrollContentBackground(.hidden).background(AppBackground()).navigationTitle(Text(LocalizedStringKey("Edit loan"))).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){guard loan.valid else{invalid=true;return};if model.save(loan){dismiss()}else{invalid=true}}.accessibilityIdentifier("saveRecord")}}}}
}
