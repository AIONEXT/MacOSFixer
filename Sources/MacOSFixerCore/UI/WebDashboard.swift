import Foundation
import Network
import AppKit

final class DashboardDataCache: @unchecked Sendable {
    private var overviewJSON: String = "{\"status\":\"loading\"}"
    private var diagnosticsJSON: String = "{\"status\":\"loading\"}"
    private var performanceJSON: String = "{\"status\":\"loading\"}"
    private var verificationJSON: String = "{\"status\":\"loading\"}"
    private let lock = NSLock()
    
    func updateOverview(_ json: String) {
        lock.lock()
        overviewJSON = json
        lock.unlock()
    }
    func updateDiagnostics(_ json: String) {
        lock.lock()
        diagnosticsJSON = json
        lock.unlock()
    }
    func updatePerformance(_ json: String) {
        lock.lock()
        performanceJSON = json
        lock.unlock()
    }
    func updateVerification(_ json: String) {
        lock.lock()
        verificationJSON = json
        lock.unlock()
    }
    
    func getOverview() -> String {
        lock.lock()
        defer { lock.unlock() }
        return overviewJSON
    }
    func getDiagnostics() -> String {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticsJSON
    }
    func getPerformance() -> String {
        lock.lock()
        defer { lock.unlock() }
        return performanceJSON
    }
    func getVerification() -> String {
        lock.lock()
        defer { lock.unlock() }
        return verificationJSON
    }
}

public final class WebDashboard: @unchecked Sendable {
    private let port: Int
    private var listener: NWListener?
    private let executor = CommandExecutor.shared
    private let diagnostics = SystemDiagnostics()
    private let performance = PerformanceMonitor()
    private var overview: MachineOverviewCollector?
    private let cache = DashboardDataCache()
    
    public init(port: Int = 8080) {
        self.port = port
        self.overview = MachineOverviewCollector()
    }
    
    public func start(openBrowser: Bool = true) async throws {
        print("Starting MacOSFixer Web Dashboard on port \(port)")
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)))
        
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.handleConnection(connection)
        }
        
        listener?.stateUpdateHandler = { @Sendable [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("Dashboard running at http://localhost:\(self.port)")
                if openBrowser {
                    NSWorkspace.shared.open(URL(string: "http://localhost:\(self.port)")!)
                }
            case .failed(let error):
                print("Dashboard failed: \(error)")
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
        
        await startBackgroundUpdates()
        
        try await withTaskCancellationHandler {
            try await Task.sleep(nanoseconds: UInt64.max)
        } onCancel: {
            self.listener?.cancel()
        }
    }
    
    private func startBackgroundUpdates() async {
        Task.detached { [weak self] in
            await self?.periodicUpdates()
        }
    }
    
    private func periodicUpdates() async {
        while !Task.isCancelled {
            await updateAllCache()
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }
    
    private func updateAllCache() async {
        await updateOverviewCache()
        await updateDiagnosticsCache()
        await updatePerformanceCache()
        await updateVerificationCache()
    }
    
    private func updateOverviewCache() async {
        do {
            if let overview = self.overview {
                let matrix = try await overview.generateMatrix(includeSecurity: true, includeNetwork: true)
                let json = try matrix.toJSON()
                cache.updateOverview(json)
            }
        } catch {
            cache.updateOverview("{\"error\":\"\(error.localizedDescription)\"}")
        }
    }
    
    private func updateDiagnosticsCache() async {
        do {
            let report = try await diagnostics.runFullDiagnostics(detailed: true)
            let json = try report.toJSON()
            cache.updateDiagnostics(json)
        } catch {
            cache.updateDiagnostics("{\"error\":\"\(error.localizedDescription)\"}")
        }
    }
    
    private func updatePerformanceCache() async {
        do {
            let report = try await performance.analyzePerformance(duration: 10, includeThermal: true, includePower: true)
            let json = try report.toJSON()
            cache.updatePerformance(json)
        } catch {
            cache.updatePerformance("{\"error\":\"\(error.localizedDescription)\"}")
        }
    }
    
    private func updateVerificationCache() async {
        do {
            let verification = SystemVerification()
            let summary = try await verification.runVerification(types: VerificationType.allCases, verbose: false, autoFix: false)
            let json = try summary.toJSON()
            cache.updateVerification(json)
        } catch {
            cache.updateVerification("{\"error\":\"\(error.localizedDescription)\"}")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            let request = String(data: data, encoding: .utf8) ?? ""
            let response = self.handleRequest(request)
            let responseData = response.data(using: .utf8) ?? Data()
            
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    private func handleRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return httpResponse(400, "Bad Request") }
        
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return httpResponse(400, "Bad Request") }
        
        let method = String(parts[0])
        let path = String(parts[1])
        
        guard method == "GET" else { return httpResponse(405, "Method Not Allowed") }
        
        switch path {
        case "/", "/index.html":
            return httpResponse(200, dashboardHTML(), "text/html")
        case "/api/overview":
            return httpResponse(200, cache.getOverview(), "application/json")
        case "/api/diagnostics":
            return httpResponse(200, cache.getDiagnostics(), "application/json")
        case "/api/performance":
            return httpResponse(200, cache.getPerformance(), "application/json")
        case "/api/verification":
            return httpResponse(200, cache.getVerification(), "application/json")
        case "/api/health":
            return httpResponse(200, "{\"status\":\"ok\"}", "application/json")
        default:
            return httpResponse(404, "Not Found")
        }
    }
    
    private func httpResponse(_ code: Int, _ body: String, _ contentType: String = "text/plain") -> String {
        let statusText = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][code] ?? "Unknown"
        return "HTTP/1.1 \(code) \(statusText)\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
    }
    
    private func dashboardHTML() -> String {
        return """
        <!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>MacOSFixer - System Dashboard</title><script src="https://cdn.tailwindcss.com"></script><script src="https://cdn.jsdelivr.net/npm/chart.js"></script><style>.metric-card{transition:transform 0.2s}.metric-card:hover{transform:translateY(-2px);box-shadow:0 4px 12px rgba(0,0,0,0.1)}.status-ok{color:#10b981}.status-warn{color:#f59e0b}.status-critical{color:#ef4444}.chart-container{position:relative;height:200px}.loading{opacity:0.6;pointer-events:none}</style></head><body class="bg-gray-50 min-h-screen"><nav class="bg-white shadow-sm border-b border-gray-200"><div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8"><div class="flex justify-between h-16"><div class="flex items-center"><h1 class="text-xl font-bold text-gray-900">MacOSFixer Dashboard</h1></div><div class="flex items-center space-x-4"><span id="lastUpdate" class="text-sm text-gray-500">Loading...</span><button onclick="refreshAll()" class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition">Refresh</button></div></div></div></nav><main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"><section id="overview" class="mb-8"><h2 class="text-lg font-semibold text-gray-900 mb-4">System Overview</h2><div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4" id="overviewCards"></div></section><section id="performance" class="mb-8"><h2 class="text-lg font-semibold text-gray-900 mb-4">Performance Metrics</h2><div class="grid grid-cols-1 lg:grid-cols-2 gap-6"><div class="bg-white rounded-lg shadow p-6"><h3 class="font-medium text-gray-900 mb-4">CPU Usage</h3><div class="chart-container"><canvas id="cpuChart"></canvas></div></div><div class="bg-white rounded-lg shadow p-6"><h3 class="font-medium text-gray-900 mb-4">Memory Usage</h3><div class="chart-container"><canvas id="memoryChart"></canvas></div></div><div class="bg-white rounded-lg shadow p-6"><h3 class="font-medium text-gray-900 mb-4">Disk I/O</h3><div class="chart-container"><canvas id="diskChart"></canvas></div></div><div class="bg-white rounded-lg shadow p-6"><h3 class="font-medium text-gray-900 mb-4">Network I/O</h3><div class="chart-container"><canvas id="networkChart"></canvas></div></div></div></section><section id="diagnostics" class="mb-8"><h2 class="text-lg font-semibold text-gray-900 mb-4">Diagnostics</h2><div class="bg-white rounded-lg shadow overflow-hidden"><table class="w-full"><thead class="bg-gray-50"><tr><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Category</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Issues</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Details</th></tr></thead><tbody id="diagnosticsTable" class="divide-y divide-gray-200"></tbody></table></div></section><section id="verification" class="mb-8"><h2 class="text-lg font-semibold text-gray-900 mb-4">System Verification</h2><div class="bg-white rounded-lg shadow overflow-hidden"><table class="w-full"><thead class="bg-gray-50"><tr><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Check</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Issues</th></tr></thead><tbody id="verificationTable" class="divide-y divide-gray-200"></tbody></table></div></section><section id="processes" class="mb-8"><h2 class="text-lg font-semibold text-gray-900 mb-4">Top Processes</h2><div class="bg-white rounded-lg shadow overflow-hidden"><table class="w-full"><thead class="bg-gray-50"><tr><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">PID</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Process</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">CPU %</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Memory</th><th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">User</th></tr></thead><tbody id="processesTable" class="divide-y divide-gray-200"></tbody></table></div></section></main><script>let cpuChart,memoryChart,diskChart,networkChart;let cpuHistory=[],memHistory=[],diskReadHistory=[],diskWriteHistory=[],netInHistory=[],netOutHistory=[];const maxHistoryPoints=30;async function refreshAll(){document.body.classList.add('loading');try{await Promise.all([loadOverview(),loadDiagnostics(),loadPerformance(),loadVerification(),loadProcesses()]);}catch(e){console.error('Refresh failed:',e);}document.body.classList.remove('loading');document.getElementById('lastUpdate').textContent='Updated: '+new Date().toLocaleTimeString();}async function loadOverview(){try{const res=await fetch('/api/overview');const data=await res.json();if(data.overview){renderOverview(data.overview);}}catch(e){console.error('Overview load failed:',e);}}function renderOverview(overview){const container=document.getElementById('overviewCards');const hw=overview.hardware;const sw=overview.software;const perf=overview.performance;container.innerHTML=`<div class="metric-card bg-white rounded-lg shadow p-6"><div class="text-sm text-gray-500">Model</div><div class="text-2xl font-bold text-gray-900">${hw.modelName}</div><div class="text-sm text-gray-500 mt-1">${hw.modelIdentifier}</div></div><div class="metric-card bg-white rounded-lg shadow p-6"><div class="text-sm text-gray-500">Processor</div><div class="text-2xl font-bold text-gray-900">${hw.processorName}</div><div class="text-sm text-gray-500 mt-1">${hw.totalNumberOfCores} cores @ ${hw.processorSpeed}</div></div><div class="metric-card bg-white rounded-lg shadow p-6"><div class="text-sm text-gray-500">Memory</div><div class="text-2xl font-bold text-gray-900">${hw.memory}</div><div class="text-sm text-gray-500 mt-1">macOS ${sw.osVersion} (${sw.osBuild})</div></div><div class="metric-card bg-white rounded-lg shadow p-6"><div class="text-sm text-gray-500">Uptime</div><div class="text-2xl font-bold text-gray-900">${formatUptime(sw.uptime)}</div><div class="text-sm text-gray-500 mt-1">Boot: ${new Date(sw.bootTime).toLocaleString()}</div></div>`;}async function loadDiagnostics(){try{const res=await fetch('/api/diagnostics');const data=await res.json();if(data.categories){renderDiagnostics(data.categories);}}catch(e){console.error('Diagnostics load failed:',e);}}function renderDiagnostics(categories){const tbody=document.getElementById('diagnosticsTable');tbody.innerHTML=categories.map(cat=>{const criticalCount=cat.issues.filter(i=>i.severity==='critical').length;const warningCount=cat.issues.filter(i=>i.severity==='warning').length;const infoCount=cat.issues.filter(i=>i.severity==='info').length;const statusClass=criticalCount>0?'status-critical':warningCount>0?'status-warn':'status-ok';const statusText=criticalCount>0?'Critical':warningCount>0?'Warning':'OK';return`<tr><td class="px-4 py-3 font-medium text-gray-900">${cat.name}</td><td class="px-4 py-3 ${statusClass} font-medium">${statusText}</td><td class="px-4 py-3"><span class="status-critical">${criticalCount}</span>/<span class="status-warn">${warningCount}</span>/<span class="status-ok">${infoCount}</span></td><td class="px-4 py-3 text-sm text-gray-500">${cat.issues.slice(0,2).map(i=>i.title).join(', ')}${cat.issues.length>2?'...':''}</td></tr>`;}).join('');}async function loadPerformance(){try{const res=await fetch('/api/performance');const data=await res.json();if(data.cpu){renderPerformance(data);updateCharts(data);}}catch(e){console.error('Performance load failed:',e);}}function renderPerformance(data){const bottlenecks=data.bottlenecks||[];if(bottlenecks.length>0){const alertDiv=document.getElementById('bottleneckAlert')||createBottleneckAlert();alertDiv.innerHTML=bottlenecks.map(b=>`<div class="p-3 rounded-lg ${b.severity==='critical'?'bg-red-50 border-red-200':'bg-yellow-50 border-yellow-200'} border"><div class="font-medium ${b.severity==='critical'?'text-red-800':'text-yellow-800'}">${b.type.toUpperCase()}: ${b.description}</div><div class="text-sm ${b.severity==='critical'?'text-red-600':'text-yellow-600'}">${b.recommendation}</div></div>`).join('');}}function createBottleneckAlert(){const div=document.createElement('div');div.id='bottleneckAlert';div.className='mb-6 space-y-2';document.getElementById('performance').prepend(div);return div;}function updateCharts(data){const now=new Date().toLocaleTimeString();const cpu=data.cpu;const mem=data.memory;const disks=data.disks;const network=data.network;cpuHistory.push({time:now,value:100-cpu.idle});if(cpuHistory.length>maxHistoryPoints)cpuHistory.shift();const memPercent=(mem.used/mem.total)*100;memHistory.push({time:now,value:memPercent});if(memHistory.length>maxHistoryPoints)memHistory.shift();const totalDiskRead=disks.reduce((sum,d)=>sum+d.readBytesPerSec,0);const totalDiskWrite=disks.reduce((sum,d)=>sum+d.writeBytesPerSec,0);diskReadHistory.push({time:now,value:totalDiskRead/(1024*1024)});diskWriteHistory.push({time:now,value:totalDiskWrite/(1024*1024)});if(diskReadHistory.length>maxHistoryPoints){diskReadHistory.shift();diskWriteHistory.shift();}const totalNetIn=network.reduce((sum,n)=>sum+n.bytesInPerSec,0);const totalNetOut=network.reduce((sum,n)=>sum+n.bytesOutPerSec,0);netInHistory.push({time:now,value:totalNetIn/(1024*1024)});netOutHistory.push({time:now,value:totalNetOut/(1024*1024)});if(netInHistory.length>maxHistoryPoints){netInHistory.shift();netOutHistory.shift();}renderCharts();}function renderCharts(){const commonOptions={responsive:true,maintainAspectRatio:false,plugins:{legend:{display:true,position:'top'}},scales:{x:{display:false},y:{beginAtZero:true}}};if(!cpuChart){cpuChart=new Chart(document.getElementById('cpuChart'),{type:'line',data:{labels:[],datasets:[{label:'CPU %',data:[],borderColor:'#3b82f6',backgroundColor:'rgba(59,130,246,0.1)',fill:true,tension:0.4}]},options:commonOptions});memoryChart=new Chart(document.getElementById('memoryChart'),{type:'line',data:{labels:[],datasets:[{label:'Memory %',data:[],borderColor:'#10b981',backgroundColor:'rgba(16,185,129,0.1)',fill:true,tension:0.4}]},options:commonOptions});diskChart=new Chart(document.getElementById('diskChart'),{type:'line',data:{labels:[],datasets:[{label:'Read MB/s',data:[],borderColor:'#f59e0b',backgroundColor:'rgba(245,158,11,0.1)',fill:true,tension:0.4},{label:'Write MB/s',data:[],borderColor:'#ef4444',backgroundColor:'rgba(239,68,68,0.1)',fill:true,tension:0.4}]},options:commonOptions});networkChart=new Chart(document.getElementById('networkChart'),{type:'line',data:{labels:[],datasets:[{label:'In MB/s',data:[],borderColor:'#8b5cf6',backgroundColor:'rgba(139,92,246,0.1)',fill:true,tension:0.4},{label:'Out MB/s',data:[],borderColor:'#ec4899',backgroundColor:'rgba(236,72,153,0.1)',fill:true,tension:0.4}]},options:commonOptions});}cpuChart.data.labels=cpuHistory.map(h=>h.time);cpuChart.data.datasets[0].data=cpuHistory.map(h=>h.value);cpuChart.update('none');memoryChart.data.labels=memHistory.map(h=>h.time);memoryChart.data.datasets[0].data=memHistory.map(h=>h.value);memoryChart.update('none');diskChart.data.labels=diskReadHistory.map(h=>h.time);diskChart.data.datasets[0].data=diskReadHistory.map(h=>h.value);diskChart.data.datasets[1].data=diskWriteHistory.map(h=>h.value);diskChart.update('none');networkChart.data.labels=netInHistory.map(h=>h.time);networkChart.data.datasets[0].data=netInHistory.map(h=>h.value);networkChart.data.datasets[1].data=netOutHistory.map(h=>h.value);networkChart.update('none');}async function loadVerification(){try{const res=await fetch('/api/verification');const data=await res.json();if(data.results){renderVerification(data.results);}}catch(e){console.error('Verification load failed:',e);}}function renderVerification(results){const tbody=document.getElementById('verificationTable');tbody.innerHTML=results.map(r=>{const criticalIssues=r.issues.filter(i=>i.severity==='critical').length;const warningIssues=r.issues.filter(i=>i.severity==='warning').length;const statusClass=criticalIssues>0?'status-critical':warningIssues>0?'status-warn':'status-ok';const statusText=r.passed?'Pass':'Fail';return`<tr><td class="px-4 py-3 font-medium text-gray-900">${r.type.replace(/-/g,' ')}</td><td class="px-4 py-3 ${statusClass} font-medium">${statusText}</td><td class="px-4 py-3 text-sm">${criticalIssues>0?'<span class="status-critical">'+criticalIssues+' critical</span>':''}${warningIssues>0?'<span class="status-warn">'+warningIssues+' warning</span>':''}</td></tr>`;}).join('');}async function loadProcesses(){try{const res=await fetch('/api/performance');const data=await res.json();if(data.topProcesses){renderProcesses(data.topProcesses.slice(0,15));}}catch(e){console.error('Processes load failed:',e);}}function renderProcesses(processes){const tbody=document.getElementById('processesTable');tbody.innerHTML=processes.map(p=>`<tr class="hover:bg-gray-50"><td class="px-4 py-2 text-sm text-gray-900">${p.pid}</td><td class="px-4 py-2 text-sm font-medium text-gray-900">${p.name}</td><td class="px-4 py-2 text-sm text-gray-900">${p.cpuPercent.toFixed(1)}%</td><td class="px-4 py-2 text-sm text-gray-900">${(p.memoryMB/1024).toFixed(1)} GB</td><td class="px-4 py-2 text-sm text-gray-500">${p.user}</td></tr>`).join('');}function formatUptime(seconds){const days=Math.floor(seconds/86400);const hours=Math.floor((seconds%86400)/3600);const mins=Math.floor((seconds%3600)/60);if(days>0)return days+'d '+hours+'h '+mins+'m';if(hours>0)return hours+'h '+mins+'m';return mins+'m';}setInterval(refreshAll,10000);refreshAll();</script></body></html>
        """
    }
}