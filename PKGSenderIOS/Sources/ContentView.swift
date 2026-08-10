import SwiftUI

extension Color {
    static let appBg = Color(red: 0x0f/255, green: 0x11/255, blue: 0x15/255)
    static let appCard = Color(red: 0x17/255, green: 0x1a/255, blue: 0x21/255)
    static let appAccent = Color(red: 0x4f/255, green: 0x8c/255, blue: 0xff/255)
    static let appAccent2 = Color(red: 0x2e/255, green: 0xcc/255, blue: 0x71/255)
    static let appMuted = Color(red: 0x8a/255, green: 0x8f/255, blue: 0x98/255)
    static let appDanger = Color(red: 0xff/255, green: 0x5c/255, blue: 0x5c/255)
    static let appFieldBg = Color(red: 0x0d/255, green: 0x0f/255, blue: 0x13/255)
    static let appBorder = Color(red: 0x33/255, green: 0x39/255, blue: 0x4a/255)
}

struct ContentView: View {
    @StateObject private var vm = SenderViewModel()
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("📤 PKG Sender for PS4")
                        .font(.title3).bold()
                        .foregroundColor(.white)
                    Text("Send a .pkg straight to your PS4 over FTP.")
                        .font(.caption)
                        .foregroundColor(.appMuted)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PS4 IP address").font(.caption2).foregroundColor(.appMuted)
                        TextField("192.168.1.XX", text: $vm.ps4ip)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(10)
                            .background(Color.appFieldBg)
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port").font(.caption2).foregroundColor(.appMuted)
                        TextField("2121", text: $vm.ps4port)
                            .keyboardType(.numberPad)
                            .padding(10)
                            .background(Color.appFieldBg)
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .frame(width: 80)
                    }
                }

                // Drop / pick zone
                Button {
                    showPicker = true
                } label: {
                    VStack(spacing: 4) {
                        if let name = vm.selectedFileName {
                            Text("📦 \(name)")
                                .foregroundColor(.appAccent2)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.center)
                            Text(SenderViewModel.formatSize(vm.selectedFileSize))
                                .font(.caption)
                                .foregroundColor(.appMuted)
                        } else {
                            Text("📦 Choose a .pkg file")
                                .foregroundColor(.white)
                            Text("Tap to browse your files")
                                .font(.caption)
                                .foregroundColor(.appMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(Color.appCard)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(vm.selectedFileName != nil ? Color.appAccent2 : Color.appBorder,
                                    style: StrokeStyle(lineWidth: 2, dash: vm.selectedFileName != nil ? [] : [6]))
                    )
                }
                .sheet(isPresented: $showPicker) {
                    DocumentPicker { url in
                        vm.selectFile(url: url)
                    }
                }

                Button {
                    vm.send()
                } label: {
                    Text(vm.isSending ? "Sending..." : "Send to PS4")
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(vm.selectedFileURL == nil || vm.isSending ? Color.appAccent.opacity(0.4) : Color.appAccent)
                        .foregroundColor(.white)
                        .font(.body.weight(.semibold))
                        .cornerRadius(10)
                }
                .disabled(vm.selectedFileURL == nil || vm.isSending)

                if vm.showProgress {
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.appFieldBg)
                                Capsule().fill(Color.appAccent)
                                    .frame(width: geo.size.width * CGFloat(vm.progressPercent / 100))
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text(String(format: "%.1f%%", vm.progressPercent))
                                .font(.caption2).foregroundColor(.appMuted)
                            Spacer()
                            Text(String(format: "%.1f MB/s", vm.progressSpeedMBs))
                                .font(.caption2).bold().foregroundColor(.appAccent2)
                        }
                    }
                }

                if let msg = vm.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(statusBackground(vm.statusKind))
                        .foregroundColor(statusColor(vm.statusKind))
                        .cornerRadius(8)
                }

                Text("Sends the file to the same place a USB install would use (/data/pkg). Once the transfer is done, open Package Installer on your PS4 to install it.")
                    .font(.caption2)
                    .foregroundColor(.appMuted)

                Divider().background(Color.appBorder)

                HStack {
                    Text("FILES ON THE PS4 (/data/pkg)")
                        .font(.caption2).bold()
                        .foregroundColor(.appMuted)
                    Spacer()
                    Button {
                        vm.refreshFiles()
                    } label: {
                        Text(vm.isRefreshing ? "Refreshing..." : "🔄 Refresh")
                            .font(.caption2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.appCard)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }

                VStack(spacing: 0) {
                    if vm.remoteFiles.isEmpty {
                        Text(vm.isRefreshing ? "Loading..." : "Tap Refresh to see files.")
                            .font(.caption)
                            .foregroundColor(.appMuted)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    } else {
                        ForEach(vm.remoteFiles) { file in
                            HStack {
                                Text(file.name)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(SenderViewModel.formatSize(file.size))
                                    .font(.caption2)
                                    .foregroundColor(.appMuted)
                                Button {
                                    vm.deleteFile(file)
                                } label: {
                                    Text(vm.deletingFileName == file.name ? "..." : "Delete")
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.appDanger))
                                        .foregroundColor(.appDanger)
                                }
                                .disabled(vm.deletingFileName == file.name)
                            }
                            .padding(10)
                            Divider().background(Color.appBorder.opacity(0.4))
                        }
                    }
                }
                .background(Color.appCard)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
            .padding(20)
        }
        .background(Color.appBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func statusBackground(_ kind: StatusKind) -> Color {
        switch kind {
        case .info: return Color(red: 0x1b/255, green: 0x20/255, blue: 0x30/255)
        case .success: return Color(red: 0x12/255, green: 0x3a/255, blue: 0x24/255)
        case .error: return Color(red: 0x3a/255, green: 0x17/255, blue: 0x17/255)
        }
    }

    private func statusColor(_ kind: StatusKind) -> Color {
        switch kind {
        case .info: return .appAccent
        case .success: return .appAccent2
        case .error: return .appDanger
        }
    }
}

#Preview {
    ContentView()
}
