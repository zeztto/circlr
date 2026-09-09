import Foundation

public struct AudioRouterTarget:Equatable {
    public let address:CircleAddress
    public let original:Bool
    public init(address:CircleAddress,original:Bool) {self.address=address;self.original=original}
}

public enum AudioRouterEditing {
    private static func scope(_ target:AudioRouterTarget,in project:Project)throws->(graph:SectionGraph,index:Int,useID:ID,router:AudioRouter) {
        guard case .music(let arrangementID,let useID,let nodeID)=target.address,
              arrangementID==project.activeArrangementID,
              project.arrangements.filter({$0.id==arrangementID}).count==1,
              let arrangement=project.arrangements.first(where:{$0.id==arrangementID}),
              arrangement.uses.filter({$0.id==useID}).count==1,
              let use=arrangement.uses.first(where:{$0.id==useID}),
              project.sections.filter({$0.id==use.sectionID}).count==1,
              let section=project.sections.first(where:{$0.id==use.sectionID}),
              let graph=try target.original ? section.graph:SectionGraphEditing.effective(section:section,use:use),
              graph.nodes.filter({$0.id==nodeID}).count==1,
              let index=graph.nodes.firstIndex(where:{$0.id==nodeID}),
              case .router(let router)=graph.nodes[index].content else {
            throw CirclrError("편집할 라우터의 섹션·서클과 원본 범위를 다시 확인하세요")
        }
        try router.validate()
        return (graph,index,useID,router)
    }
    public static func snapshot(_ target:AudioRouterTarget,in project:Project)throws->AudioRouter {
        try scope(target,in:project).router
    }
    public static func setGain(_ target:AudioRouterTarget,input:String,output:String,gain:Double,expectedGain:Double?=nil,in project:inout Project)throws {
        guard AudioRouter.inputs.contains(input),AudioRouter.outputs.contains(output),
              gain.isFinite,(0...GainScale.maximum).contains(gain) else {
            throw CirclrError("라우터의 입력·출력과 전송량 −∞–12.0412 dB 범위를 확인하세요")
        }
        let current=try snapshot(target,in:project)
        let index=current.routes.firstIndex{$0.input==input && $0.output==output}
        let previous=index.map{current.routes[$0].gain} ?? 0
        if let expectedGain,expectedGain != previous {throw CirclrError("라우터 전송량이 변경되었습니다. 현재 값에서 다시 입력하세요")}
        // An unchanged explicit zero route is preserved, including its position.
        guard previous != gain else{return}
        var next=current
        if let index {
            if gain==0 {next.routes.remove(at:index)}
            else {next.routes[index].gain=gain}
        }else if gain != 0 {next.routes.append(.init(input:input,output:output,gain:gain))}
        try replace(target,router:next,expected:current,in:&project)
    }
    public static func replace(_ target:AudioRouterTarget,router:AudioRouter,expected:AudioRouter?=nil,in project:inout Project)throws {
        try router.validate()
        let current=try scope(target,in:project)
        if let expected,expected != current.router {throw CirclrError("라우터 경로가 변경되었습니다. 현재 경로에서 다시 적용하세요")}
        guard router != current.router else{return}
        var graph=current.graph
        graph.nodes[current.index].content = .router(router)
        // This validates every affected use before committing the candidate project.
        try SectionGraphEditing.set(graph,useID:current.useID,original:target.original,in:&project)
    }
}
