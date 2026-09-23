// Standalone App-target smoke:
// xcrun swiftc Sources/CirclrApp/AgentSocket.swift Sources/CirclrApp/AgentEndpointSelection.swift Tests/AgentEndpointSelectionSmoke.swift -o /tmp/circlr-agent-endpoint-smoke && /tmp/circlr-agent-endpoint-smoke
import Foundation
import Darwin

@main struct AgentEndpointSelectionSmoke {
    static func require(_ condition:Bool,_ message:String) throws {
        guard condition else {throw NSError(domain:"AgentEndpointSelectionSmoke",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    }
    static func main() throws {
        let root=URL(fileURLWithPath:"/tmp/cas-"+String(UUID().uuidString.prefix(8)),isDirectory:true)
        let directory=root.appendingPathComponent("Agent",isDirectory:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let old=try AgentSocket(directory:directory){_,reply in reply(Data(#"{"ok":true}"#.utf8))}
        let oldPath=old.path
        var oldInfo=stat();try require(lstat(oldPath,&oldInfo)==0,"old socket missing")
        let new=try AgentSocket(directory:directory,name:".r1a2b3c4d"){_,reply in reply(Data(#"{"ok":true}"#.utf8))}
        let runID=UUID().uuidString
        let selection=AgentEndpointSelection(endpoint:".r1a2b3c4d",runID:runID,bundleID:"com.circlr.portfocusqa")
        try AgentEndpointSelection.publish(selection,in:directory)
        let path=directory.appendingPathComponent("selected.json")
        let decoded=try JSONDecoder().decode(AgentEndpointSelection.self,from:Data(contentsOf:path))
        try require(decoded==selection,"published selection changed")
        try require(AgentEndpointSelection.current(in:directory)==selection,"current selection unreadable")
        try require(old.ownsPublishedPath && new.ownsPublishedPath,"live socket ownership lost")
        var info=stat();try require(lstat(path.path,&info)==0,"selection missing")
        try require(info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),"selection is not regular")
        try require(info.st_uid==getuid() && info.st_mode & 0o077==0,"selection permissions widened")
        var currentOld=stat();try require(lstat(oldPath,&currentOld)==0 && currentOld.st_ino==oldInfo.st_ino,"old socket changed")
        try require(FileManager.default.fileExists(atPath:new.path),"alternate socket missing")
        let changed=AgentEndpointSelection(endpoint:"agent.sock",runID:UUID().uuidString,bundleID:"com.circlr.portfocusqa")
        try AgentEndpointSelection.publish(changed,in:directory)
        try require(JSONDecoder().decode(AgentEndpointSelection.self,from:Data(contentsOf:path))==changed,"atomic replacement failed")
        try require(AgentEndpointSelection.current(in:directory)==changed,"current selection was not refreshed")
        let saved=directory.appendingPathComponent("selected-saved.json")
        try FileManager.default.moveItem(at:path,to:saved)
        try require(Darwin.mkfifo(path.path,0o600)==0,"FIFO fixture failed")
        try require(AgentEndpointSelection.current(in:directory)==nil,"FIFO selected manifest accepted")
        try FileManager.default.removeItem(at:path)
        try FileManager.default.createSymbolicLink(at:path,withDestinationURL:saved)
        try require(AgentEndpointSelection.current(in:directory)==nil,"symlink selected manifest accepted")
        try FileManager.default.removeItem(at:path)
        try FileManager.default.moveItem(at:saved,to:path)

        let symlink=root.appendingPathComponent("Agent-link")
        try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:directory)
        do {
            try AgentEndpointSelection.publish(selection,in:symlink)
            throw NSError(domain:"AgentEndpointSelectionSmoke",code:2,userInfo:[NSLocalizedDescriptionKey:"symlink Agent directory accepted"])
        } catch let error as NSError where error.domain=="CirclrAgentEndpoint" && error.code==2 {}
        withExtendedLifetime(old){};withExtendedLifetime(new){}
        print("Agent endpoint manifest, permissions, no-replace socket, and symlink rejection PASS")
    }
}
