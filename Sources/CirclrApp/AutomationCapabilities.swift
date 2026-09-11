import CirclrCore

extension AppStore {
    var automationDescriptors:[[String:Any]] {
        guard let node=automationNode else{return []}
        return AutomationParameter.allCases.filter{$0.supports(node:node,in:project)}.map { parameter in
            ["id":parameter.rawValue,"label":parameter.label,"displayUnit":parameter.unit,
             "valueUnit":parameter == .gain ? "linearGain":parameter == .pan ? "normalizedPan":parameter == .synthResonance ? "normalizedResonance":"Hz",
             "minimum":parameter.range.lowerBound,"maximum":parameter.range.upperBound,
             "defaultValue":parameter.fallback(node:node,in:project)]
        }
    }
}
