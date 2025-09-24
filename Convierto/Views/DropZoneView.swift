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
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)

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
        VStack(spacing: 24) {
            HStack(alignment: .center, spacing: 24) {
                dragAndDropColumn

                VStack(spacing: 16) {
                    Button(action: onSelectFiles) {
                        Text("Convert →")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!hasFiles)
                    .opacity(hasFiles ? 1 : 0.5)

                    Text(hasFiles ? "Ready when you are" : "Add files to get started")
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
                        .fill(showError ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .frame(width: 56, height: 56)

                    Image(systemName: showError ? "exclamationmark.circle.fill" :
                            isDragging ? "arrow.down.circle.fill" : "square.and.arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .medium))
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
                            isDragging ? "Release to Convert" : "Drag & drop files here")
                        .font(.system(size: 16, weight: .semibold))

                    if showError {
                        Text("Try dropping the file again or choose another")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !isDragging {
                        Text("We’ll automatically convert supported files for you")
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
        .padding(24)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Prefer manual selection?")
                .font(.system(size: 15, weight: .semibold))

            Button(action: onSelectFiles) {
                Text("Select…")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Label("Browse your library", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Label("Supports images, video, audio & PDF", systemImage: "doc.richtext")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
