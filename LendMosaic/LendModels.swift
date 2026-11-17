import Foundation
import Observation
struct Loan:Codable,Identifiable,Equatable {
 var id=UUID();var name="";var borrower="";var category="";var lent=Calendar.current.startOfDay(for:Date());var due=Calendar.current.date(byAdding:.day,value:7,to:Calendar.current.startOfDay(for:Date()))!;var returned:Date?;var notes=""
 var valid:Bool{!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !borrower.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !category.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && lent<=Date() && due>=lent && (returned==nil || returned!>=lent)}
 func days(at date:Date=Date())->Int{Calendar.current.dateComponents([.day],from:Calendar.current.startOfDay(for:date),to:Calendar.current.startOfDay(for:due)).day ?? 0}
 func status(at date:Date=Date())->String{returned != nil ? "Returned":days(at:date)<0 ? "Overdue":days(at:date)==0 ? "Due today":"On loan"}
}
@Observable @MainActor final class LendModel {
 let repository:Repository<[Loan]>
 init(url:URL?=nil){repository=Repository(initial:[],url:url)}
 var records:[Loan]{repository.value}
 var active:[Loan]{records.filter{$0.returned==nil}.sorted{$0.due<$1.due}}
 var history:[Loan]{records.filter{$0.returned != nil}.sorted{($0.returned ?? .distantPast)>($1.returned ?? .distantPast)}}
 @discardableResult func save(_ p:Loan)->Bool{guard p.valid else{return false};var r=records;if let i=r.firstIndex(where:{$0.id==p.id}){r[i]=p}else{r.append(p)};return repository.update(r)}
 @discardableResult func returnItem(_ id:UUID,at date:Date=Date())->Bool{var r=records;guard let i=r.firstIndex(where:{$0.id==id}),r[i].returned==nil,date>=r[i].lent else{return false};r[i].returned=date;return repository.update(r)}
 @discardableResult func reopen(_ id:UUID)->Bool{var r=records;guard let i=r.firstIndex(where:{$0.id==id}),r[i].returned != nil else{return false};r[i].returned=nil;return repository.update(r)}
 func delete(_ p:Loan){_ = repository.update(records.filter{$0.id != p.id})}
 func seed(){guard records.isEmpty else{return};let today=Calendar.current.startOfDay(for:Date());func day(_ n:Int)->Date{Calendar.current.date(byAdding:.day,value:n,to:today)!};_ = repository.update([Loan(name:"Trail camera",borrower:"Jordan Lee",category:"Photography",lent:day(-5),due:day(2),notes:"Fictional sample. Strap and spare battery included."),Loan(name:"Cordless drill",borrower:"Sam Rivera",category:"Tools",lent:day(-10),due:day(-1)),Loan(name:"Field guide",borrower:"Riley Morgan",category:"Books",lent:day(-14),due:day(-3),returned:day(-4))])}
}
