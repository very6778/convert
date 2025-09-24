import SwiftUI
import UniformTypeIdentifiers
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Convierto",
    category: "DropZone"
)

struct DropZoneView: View {
    @Binding var isDragging: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String?
    let selectedFormat: UTType
    let hasFiles: Bool
    let onFilesSelected: ([URL]) -> Void

    private let dropDelegate: FileDropDelegate
    @Environment(\.colorScheme) private var colorScheme

    init(
        isDragging: Binding<Bool>,
        showError: Binding<Bool>,
        errorMessage: Binding<String?>,
        selectedFormat: UTType,
        hasFiles: Bool,
        onFilesSelected: @escaping ([URL]) -> Void
    ) {
        self._isDragging = isDragging
        self._showError = showError
        self._errorMessage = errorMessage
        self.selectedFormat = selectedFormat
        self.hasFiles = hasFiles
        self.onFilesSelected = onFilesSelected

        self.dropDelegate = FileDropDelegate(
            isDragging: isDragging,
            supportedTypes: [.fileURL],
            handleDrop: { providers in
                Task {
                    do {
                        let handler = FileDropHandler()
                        let urls = try await handler.handleProviders(providers, outputFormat: selectedFormat)
                        onFilesSelected(urls)
                        
                        await MainActor.run {
                            withAnimation {
                                showError.wrappedValue = false
                                errorMessage.wrappedValue = nil
                            }
                        }
                    } catch {
                        logger.error("Drop handling failed: \(error.localizedDescription)")
                        await MainActor.run {
                            withAnimation {
                                errorMessage.wrappedValue = error.localizedDescription
                                showError.wrappedValue = true
                            }
                        }
                        
                        // Auto-hide error after 3 seconds
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run {
                            withAnimation {
                                showError.wrappedValue = false
                                errorMessage.wrappedValue = nil
                            }
                        }
                    }
                }
            }
        )
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.08), radius: 26, x: 0, y: 18)

            DropZoneContent(
                isDragging: isDragging,
                showError: showError,
                errorMessage: errorMessage,
                hasFiles: hasFiles,
                onSelectFiles: selectFiles,
                onTryAgain: {
                    withAnimation {
                        showError = false
                        errorMessage = nil
                        isDragging = false
                    }
                },
                onStartOver: {
                    withAnimation {
                        showError = false
                        errorMessage = nil
                        isDragging = false
                        onFilesSelected([])  // Clear any selected files
                    }
                }
            )
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectFiles)
        .onDrop(of: [.fileURL], delegate: dropDelegate)
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .audio, .pdf]
        
        Task { @MainActor in
            guard let window = NSApp.windows.first else { return }
            let response = await panel.beginSheetModal(for: window)
            
            if response == .OK {
                onFilesSelected(panel.urls)
            }
        }
    }
}

private struct DropZoneContent: View {
    let isDragging: Bool
    let showError: Bool
    let errorMessage: String?
    let hasFiles: Bool
    let onSelectFiles: () -> Void
    let onTryAgain: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .top, spacing: 28) {
                dragAndDropColumn

                VStack(spacing: 14) {
                    Button(action: onSelectFiles) {
                        HStack(spacing: 10) {
                            Text("Convert")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(hasFiles ? Color.accentColor : Color.accentColor.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(hasFiles ? 0.28 : 0.16), lineWidth: 1)
                        )
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.accentColor.opacity(hasFiles ? 0.35 : 0.12), radius: 14, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasFiles)
                    .opacity(hasFiles ? 1 : 0.6)

                    Text(hasFiles ? "Files ready to convert" : "Add files to get started")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 180)

                selectionColumn
            }

            if !isDragging && !showError {
                HStack(spacing: 4) {
                    Text("Press")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))

                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 11, weight: .medium))
                        Text("K")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                            )
                    )

                    Text("to browse formats")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .opacity(0.8)
                .transition(.opacity)
            }
        }
    }

    private var dragAndDropColumn: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(showError ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)

                    Image(systemName: showError ? "exclamationmark.circle.fill" :
                            isDragging ? "arrow.down.circle.fill" : "square.and.arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: showError ? [.red, .red.opacity(0.8)] :
                                    [.accentColor, .accentColor.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .symbolEffect(.bounce, value: isDragging)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(showError ? (errorMessage ?? "Error") :
                            isDragging ? "Release to convert" : "Drag & drop files here")
                        .font(.system(size: 15, weight: .medium))

                    if showError {
                        Text("Try dropping the file again or choose another")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !isDragging {
                        Text("Supported files convert automatically once they land here")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if showError {
                HStack(spacing: 12) {
                    Button(action: onStartOver) {
                        Text("Start Over")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(action: onTryAgain) {
                        Text("Try Again")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    showError ? Color.red.opacity(0.5) :
                        (isDragging ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25)),
                    style: StrokeStyle(lineWidth: showError ? 2 : 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
        )
    }

    private var selectionColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prefer manual selection?")
                .font(.system(size: 15, weight: .semibold))

            Button(action: onSelectFiles) {
                HStack(spacing: 6) {
                    Text("Select…")
                    Image(systemName: "folder")
                }
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)

            Text("Browse your library for images, videos, audio or PDFs.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}
