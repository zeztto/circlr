import Foundation

/// A delayed permission reply may only start the recording request that is still pending.
public struct RecordingAuthorization {
    public struct Request:Equatable,Sendable {
        public let id:UUID
        public let projectID:ID
        public let revision:Int
        public let address:CircleAddress
        public let trackID:ID
        public let laneID:ID?
    }
    public private(set) var pending:Request?
    public init(){}
    public mutating func begin(projectID:ID,revision:Int,address:CircleAddress,trackID:ID,laneID:ID?)->Request {
        let request=Request(id:UUID(),projectID:projectID,revision:revision,address:address,trackID:trackID,laneID:laneID);pending=request;return request
    }
    public mutating func cancel(){pending=nil}
    public func matches(_ request:Request,projectID:ID,revision:Int,address:CircleAddress?,trackID:ID?,laneID:ID?)->Bool {
        pending?.id==request.id && request.projectID==projectID && request.revision==revision && request.address==address && request.trackID==trackID && request.laneID==laneID
    }
    public mutating func consume(_ request:Request,projectID:ID,revision:Int,address:CircleAddress?,trackID:ID?,laneID:ID?)->Bool {
        guard pending?.id==request.id else{return false}
        let valid=matches(request,projectID:projectID,revision:revision,address:address,trackID:trackID,laneID:laneID);pending=nil;return valid
    }
}
