import AppKit
import CoreLocation
import CoreWLAN

final class ScanDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var window: NSWindow!
    var label: NSTextField!
    var started = false
    var finished = false
    var output: URL!
    var interfaceName = "en0"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count >= 2 else {
            NSApplication.shared.terminate(nil)
            return
        }
        output = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.count >= 3 { interfaceName = CommandLine.arguments[2] }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 130),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "WLAN Scan Helper"
        label = NSTextField(wrappingLabelWithString: "请在系统弹窗中允许定位，以读取附近 Wi-Fi 的名称。")
        label.frame = NSRect(x: 24, y: 35, width: 432, height: 65)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        manager.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            self.finish(["error": "等待定位授权或扫描超时。请在定位服务中检查 WLAN Scan Helper，再重新扫描。"])
        }
        if !CLLocationManager.locationServicesEnabled() {
            finish(["error": "系统定位服务未开启。请在系统设置的隐私与安全性中开启定位服务。"])
            return
        }
        checkAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard output != nil else { return }
        checkAuthorization()
    }

    func checkAuthorization() {
        guard !started && !finished else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            started = true
            label.stringValue = "已获得定位权限，正在扫描附近 Wi-Fi…"
            DispatchQueue.global(qos: .userInitiated).async { self.scan() }
        case .denied, .restricted:
            finish(["error": "定位权限未获允许。请打开系统设置 → 隐私与安全性 → 定位服务，允许 WLAN Scan Helper，然后重新扫描。"])
        @unknown default:
            finish(["error": "系统返回未知定位授权状态。"])
        }
    }

    func scan() {
        do {
            guard let iface = CWWiFiClient.shared().interface(withName: interfaceName) else {
                finish(["error": "找不到指定的无线网卡。"]); return
            }
            guard iface.powerOn() else {
                finish(["error": "Wi-Fi 未开启。"]); return
            }
            let networks = try iface.scanForNetworks(withName: nil)
            let visible = networks.compactMap { network -> [String: Any]? in
                guard let ssid = network.ssid, !ssid.isEmpty else { return nil }
                let security: String
                if network.supportsSecurity(.wpa3Personal) { security = "WPA3" }
                else if network.supportsSecurity(.wpa2Personal) { security = "WPA2" }
                else if network.supportsSecurity(.wpaPersonal) { security = "WPA" }
                else if network.supportsSecurity(.wpa3Enterprise) { security = "WPA3 Enterprise" }
                else if network.supportsSecurity(.wpa2Enterprise) { security = "WPA2 Enterprise" }
                else if network.supportsSecurity(.wpaEnterprise) { security = "WPA Enterprise" }
                else if network.supportsSecurity(.none) { security = "None" }
                else { security = "Unknown" }
                return ["ssid": ssid, "bssid": network.bssid ?? "",
                        "rssi": network.rssiValue, "channel": network.wlanChannel?.channelNumber ?? 0,
                        "security": security]
            }
            if !networks.isEmpty && visible.isEmpty {
                finish(["error": "定位已授权，但系统仍隐藏所有 Wi-Fi 名称。可能存在当前 macOS 版本的兼容性问题。"])
                return
            }
            finish(["networks": visible, "total": networks.count])
        } catch {
            finish(["error": "CoreWLAN 扫描失败：\(error.localizedDescription)"])
        }
    }

    func finish(_ result: [String: Any]) {
        DispatchQueue.main.async {
            guard !self.finished else { return }
            self.finished = true
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                try data.write(to: self.output, options: [.atomic])
            } catch {
                fputs("无法保存扫描结果：\(error.localizedDescription)\n", stderr)
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

let application = NSApplication.shared
let delegate = ScanDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
