import Foundation

@main struct ConsolePreferencesChecks {
    static func main() {
        var count=0
        func check(_ condition:Bool,_ label:String){precondition(condition,label);count+=1}
        check(ConsolePreferences.decodeOpen(nil),"missing open")
        check(ConsolePreferences.decodeOpen(true),"true")
        check(!ConsolePreferences.decodeOpen(false),"false")
        for value:Any in [0,1,"false",[false],NSNull()] {check(ConsolePreferences.decodeOpen(value),"invalid open type")}
        for value:Any? in [nil,true,false,"180",NSNull(),Double.nan,Double.infinity,-Double.infinity] {
            check(ConsolePreferences.decodeHeight(value)==122,"invalid height")
        }
        for (value,expected) in [(0.0,40.0),(39.0,40.0),(40.0,40.0),(122.5,122.5),(180.0,180.0),(181.0,180.0)] {
            check(ConsolePreferences.decodeHeight(value)==expected,"height clamp")
        }
        let firstName="com.circlr.qa.console."+UUID().uuidString
        let secondName="com.circlr.qa.console."+UUID().uuidString
        let first=UserDefaults(suiteName:firstName)!,second=UserDefaults(suiteName:secondName)!
        defer {first.removePersistentDomain(forName:firstName);second.removePersistentDomain(forName:secondName)}
        let a=ConsolePreferences(defaults:first),b=ConsolePreferences(defaults:second)
        check(a.isOpen && a.logHeight==122,"fresh defaults")
        a.saveOpen(false);a.saveHeight(180)
        check(!a.isOpen && a.logHeight==180,"stored values")
        check(b.isOpen && b.logHeight==122,"separate domain")
        check(first.synchronize(),"flush test suite")
        let reloaded=ConsolePreferences(defaults:UserDefaults(suiteName:firstName)!)
        check(!reloaded.isOpen && reloaded.logHeight==180,"new defaults instance")
        first.set("false",forKey:ConsolePreferences.openKey);first.set(true,forKey:ConsolePreferences.heightKey)
        check(a.isOpen && a.logHeight==122,"malformed persistent types")
        a.saveHeight(-100);check(a.logHeight==40,"save clamp low")
        a.saveHeight(Double.infinity);check(a.logHeight==122,"save nonfinite")
        a.saveHeight(1000);a.saveOpen(true);check(a.isOpen && a.logHeight==180,"save clamp high")
        print("ConsolePreferences checks PASS: \(count); isolated temporary suites only")
    }
}
