import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FormatSelectorView: View {
    let selectedInputFormat: UTType?
    @Binding var selectedOutputFormat: UTType
    let supportedTypes: [String: [UTType]]
    @State private var showError = false
    @State private var errorMessage: String?
    
    var body: some View {
        HStack(spacing: 20) {
            if let inputFormat = selectedInputFormat {
                InputFormatPill(format: inputFormat)
                
                Image(systemName: "arrow.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            OutputFormatSelector(
                selectedOutputFormat: $selectedOutputFormat,
                supportedTypes: supportedTypes,
                showError: showError,
                errorMessage: errorMessage
            )
        }
        .onChange(of: selectedOutputFormat) { oldValue, newValue in
            validateFormatCompatibility(input: selectedInputFormat, output: newValue)
        }
    }
    
    private func validateFormatCompatibility(input: UTType?, output: UTType) {
        guard let input = input else { return }
        
        let isCompatible = checkFormatCompatibility(input: input, output: output)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showError = !isCompatible
            errorMessage = isCompatible ? nil : "Cannot convert between these formats"
        }
    }
}

struct InputFormatPill: View {
    let format: UTType
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getFormatIcon(for: format))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.secondary.opacity(0.8), .secondary.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .font(.system(size: 14, weight: .medium))
            
            Text(format.localizedDescription ?? "Unknown Format")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .opacity(0.4)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            }
        )
    }
}

struct OutputFormatSelector: View {
    @Binding var selectedOutputFormat: UTType
    let supportedTypes: [String: [UTType]]
    let showError: Bool
    let errorMessage: String?
    
    @State private var isMenuOpen = false
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Selector Button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isMenuOpen.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Selected Format Icon
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: getFormatIcon(for: selectedOutputFormat))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Convert to")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(selectedOutputFormat.localizedDescription ?? "Select Format")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isMenuOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? 
                                Color.black.opacity(0.3) : 
                                Color.white.opacity(0.8))
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(isHovered ? 0.2 : 0.1), 
                                   lineWidth: 1)
                    }
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            
            // Format Menu (expands below)
            if isMenuOpen {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(supportedTypes.keys.sorted(), id: \.self) { category in
                            // Category Header
                            Text(category)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                            
                            // Format Grid
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(supportedTypes[category] ?? [], id: \.identifier) { format in
                                    FormatButton(
                                        format: format,
                                        isSelected: format == selectedOutputFormat,
                                        action: {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedOutputFormat = format
                                                isMenuOpen = false
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .frame(maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? 
                            Color.black.opacity(0.3) : 
                            Color.white.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if showError {
                Text(errorMessage ?? "Error")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                    .offset(y: -30)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    func getFormatIcon(for format: UTType) -> String {
        FormatSelectorMenu.getFormatIcon(for: format)
    }
}

struct ContentView: View {
    @StateObject private var processor = MultiFileProcessor()
    @State private var isDragging = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var selectedOutputFormat: UTType = .jpeg
    @State private var isMultiFileMode = false
    @State private var isFormatSelectorPresented = false
    @State private var isSmartCompressEnabled = false
    @State private var smartCompressionCodec: ConversionSettings.SmartCompressionCodec = .hevc
    @Environment(\.colorScheme) private var colorScheme
    
    private let supportedTypes: [UTType] = Array(Set([
        .jpeg, .png, .heic, .tiff, .gif, .bmp, .webP,
        .mpeg4Movie, .quickTimeMovie, .avi,
        .mp3, .wav, .aiff, .m4a, .aac,
        .pdf
    ])).sorted { $0.identifier < $1.identifier }
    
    private var supportedFormats: [String: [UTType]] {
        [
            "Images": [.jpeg, .png, .heic, .tiff, .gif, .bmp, .webP],
            "Videos": [.mpeg4Movie, .quickTimeMovie, .avi],
            "Audio": [.mp3, .wav, .aiff, .m4a, .aac],
            "Documents": [.pdf]
        ]
    }
    
    private func supportedFormats(for operation: String) -> [String: [UTType]] {
        let formats: [String: [UTType]] = [
            "Images": [
                UTType.jpeg,
                UTType.png,
                UTType.heic,
                UTType.tiff,
                UTType.gif,
                UTType.bmp,
                UTType.webP
            ],
            "Documents": [UTType.pdf],
            "Video": [
                UTType.mpeg4Movie,
                UTType.quickTimeMovie,
                UTType.avi
            ],
            "Audio": [
                UTType.mp3,
                UTType.wav,
                UTType.aiff,
                UTType.m4a,
                UTType.aac
            ]
        ]
        return formats
    }
    
    private var categorizedTypes: [String: [UTType]] {
        Dictionary(grouping: supportedTypes) { type in
            if type.conforms(to: .image) {
                return "Images"
            } else if type.conforms(to: .audio) {
                return "Audio"
            } else if type.conforms(to: .video) {
                return "Video"
            } else if type.conforms(to: .text) {
                return "Documents"
            } else {
                return "Other"
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .opacity(0.8)
                .ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 24) {
                SourcePanel(
                    processor: processor,
                    isDragging: $isDragging,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    selectedFormat: selectedOutputFormat,
                    onFilesSelected: { urls in
                        Task { await handleSelectedFiles(urls) }
                    },
                    onClearAll: clearAllFiles
                )
                
                VStack(alignment: .leading, spacing: 20) {
                    FormatSelectorView(
                        selectedInputFormat: nil,
                        selectedOutputFormat: $selectedOutputFormat,
                        supportedTypes: supportedFormats(for: "output")
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    SmartCompressControls(
                        isOn: $isSmartCompressEnabled,
                        codec: $smartCompressionCodec,
                        isEnabled: selectedOutputFormat.conforms(to: .audiovisualContent)
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Group {
                        if processor.isProcessing {
                            ProcessingView(onCancel: {
                                clearAllFiles()
                            })
                            .frame(maxWidth: .infinity)
                        } else if let result = processor.processingResult {
                            ResultView(result: result) {
                                Task {
                                    do {
                                        try await processor.saveConvertedFile(url: result.outputURL, originalName: result.originalFileName)
                                        await clearAllFiles()
                                    } catch {
                                        withAnimation(.spring(response: 0.3)) {
                                            errorMessage = error.localizedDescription
                                            showError = true
                                        }
                                    }
                                }
                            } onReset: {
                                clearAllFiles()
                            }
                            .frame(maxWidth: .infinity)
                        } else if processor.files.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ready when you are")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Drop files on the left and choose your desired output format to begin.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Queued Files: \(processor.files.count)")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Conversions start automatically. Adjust output settings above or manage files on the left.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
                    
                    if isMultiFileMode && !processor.files.isEmpty {
                        Divider()
                        HStack {
                            Button {
                                Task {
                                    do {
                                        try await processor.saveAllFilesToFolder()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save All")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: clearAllFiles) {
                                Text("Clear Queue")
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .infoPaneCard()
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            
            if isFormatSelectorPresented {
                FormatSelectorMenu(
                    selectedFormat: $selectedOutputFormat,
                    supportedTypes: categorizedTypes,
                    isPresented: $isFormatSelectorPresented
                )
                .transition(.opacity)
            }
        }
        .onDrop(
            of: [.fileURL],
            delegate: FileDropDelegate(
                isDragging: $isDragging,
                supportedTypes: supportedTypes,
                handleDrop: handleFilesSelected
            )
        )
        .onChange(of: selectedOutputFormat) { newFormat in
            processor.selectedOutputFormat = newFormat
            if !newFormat.conforms(to: .audiovisualContent) && isSmartCompressEnabled {
                isSmartCompressEnabled = false
            }
        }
        .onChange(of: isSmartCompressEnabled) { newValue in
            processor.setSmartCompression(newValue)
        }
        .onChange(of: smartCompressionCodec) { newValue in
            processor.setSmartCompressionCodec(newValue)
        }
        .keyboardShortcut("k", modifiers: [.command])
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "k" {
                    isFormatSelectorPresented.toggle()
                    return nil
                }
                return event
            }
            processor.setSmartCompression(isSmartCompressEnabled)
            processor.setSmartCompressionCodec(smartCompressionCodec)
        }
    }
    
    @MainActor
    private func clearAllFiles() {
        withAnimation(.spring(response: 0.3)) {
            processor.cancelProcessing()
            processor.clearFiles()
            processor.processingResult = nil
            processor.conversionResult = nil
            processor.progress = 0
            processor.isProcessing = false
            processor.error = nil
            isMultiFileMode = false
            showError = false
            errorMessage = nil
        }
    }
    
    @MainActor
    private func handleSelectedFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            clearAllFiles()
            return
        }
        
        if urls.count > 1 {
            clearAllFiles()
            withAnimation(.spring(response: 0.3)) {
                isMultiFileMode = true
                processor.selectedOutputFormat = selectedOutputFormat
            }
            
            for url in urls {
                do {
                    _ = try await processor.processFile(url, outputFormat: selectedOutputFormat)
                } catch {
                    withAnimation(.spring(response: 0.3)) {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        } else if let url = urls.first {
            clearAllFiles()
            processor.selectedOutputFormat = selectedOutputFormat
            do {
                let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
                guard let inputType = resourceValues.contentType else {
                    throw ConversionError.invalidInput
                }
                
                // Validate input type
                let allSupportedTypes = supportedFormats(for: "input").values.flatMap { $0 }
                guard allSupportedTypes.contains(where: { inputType.conforms(to: $0) }) else {
                    throw ConversionError.unsupportedFormat(format: inputType)
                }
                
                withAnimation {
                    processor.isProcessing = true
                }
                
                do {
                    let result = try await processor.processFile(url, outputFormat: selectedOutputFormat)
                    
                    withAnimation(.spring(response: 0.3)) {
                        processor.isProcessing = false
                        processor.processingResult = result
                    }
                } catch {
                    withAnimation(.spring(response: 0.3)) {
                        processor.isProcessing = false
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func shareResult(_ url: URL) {
        let picker = NSSavePanel()
        picker.nameFieldStringValue = url.lastPathComponent
        
        Task { @MainActor in
            guard let window = NSApp.windows.first else { return }
            let response = await picker.beginSheetModal(for: window)
            
            if response == .OK, let saveURL = picker.url {
                do {
                    try FileManager.default.copyItem(at: url, to: saveURL)
                } catch {
                    showError = true
                    errorMessage = "Failed to save file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleFilesSelected(_ providers: [NSItemProvider]) {
        Task {
            do {
                let handler = FileDropHandler()
                let urls = try await handler.handleProviders(providers, outputFormat: selectedOutputFormat)
                await handleSelectedFiles(urls)
            } catch {
                await MainActor.run {
                    withAnimation {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
}

struct SourcePanel: View {
    @ObservedObject var processor: MultiFileProcessor
    @Binding var isDragging: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String?
    let selectedFormat: UTType
    let onFilesSelected: ([URL]) -> Void
    let onClearAll: () -> Void
    
    private var files: [FileProcessingState] { processor.files }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Source Files")
                .font(.system(size: 18, weight: .semibold))
            
            DropZoneView(
                isDragging: $isDragging,
                showError: $showError,
                errorMessage: $errorMessage,
                selectedFormat: selectedFormat,
                hasFiles: !files.isEmpty
            ) { urls in
                if urls.isEmpty {
                    onClearAll()
                } else {
                    onFilesSelected(urls)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            
            if files.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No files added yet")
                        .font(.system(size: 14, weight: .medium))
                    Text("Drag and drop files above or click to browse.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("Selected (\(files.count))")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button(action: onClearAll) {
                        Text("Clear All")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                }
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(files) { file in
                            SourceFileRow(
                                file: file,
                                onRemove: {
                                    if let index = processor.files.firstIndex(where: { $0.id == file.id }) {
                                        withAnimation(.spring(response: 0.3)) {
                                            processor.removeFile(at: index)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }
        }
        .primaryPaneCard()
        .frame(maxWidth: .infinity)
    }
}

private struct PrimaryPaneCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(24)
            .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .shadow(color: shadowColor, radius: 22, x: 0, y: 18)
            )
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.06)
        }
        return Color(NSColor.windowBackgroundColor).opacity(0.95)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.08)
    }
}

private struct InfoPaneCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(cardStroke, lineWidth: 1)
                    )
            )
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.04)
        }
        return Color.white.opacity(0.75)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}

private extension View {
    func primaryPaneCard() -> some View {
        modifier(PrimaryPaneCardModifier())
    }

    func infoPaneCard() -> some View {
        modifier(InfoPaneCardModifier())
    }
}

struct SourceFileRow: View {
    let file: FileProcessingState
    let onRemove: () -> Void
    
    private var progressValue: Double {
        max(0, min(1, file.progress))
    }
    
    private var progressColor: Color {
        switch file.stage {
        case .completed:
            return .green
        case .failed:
            return .red
        default:
            return .accentColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.displayFileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.stage.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(file.isProcessing ? 0.4 : 1.0)
                .disabled(file.isProcessing)
            }
            
            ProgressView(value: progressValue)
                .tint(progressColor)
            
            HStack {
                Text(file.result?.fileType.localizedDescription ?? file.fileTypeText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progressValue * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
    }
}

private extension FileProcessingState {
    var fileTypeText: String {
        url.pathExtension.isEmpty ? "" : url.pathExtension.uppercased()
    }
}

struct FormatPill: View {
    let format: UTType
    let isInput: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getFormatIcon(for: format))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isInput ? .secondary : .accentColor)
            
            Text(format.localizedDescription ?? "Unknown Format")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .opacity(0.4)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            }
        )
    }
}

struct SmartCompressControls: View {
    @Binding var isOn: Bool
    @Binding var codec: ConversionSettings.SmartCompressionCodec
    var isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Compress")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Adaptive bitrate with optimized codec")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .disabled(!isEnabled)
            
            if isOn && isEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Codec")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("Codec", selection: $codec) {
                        ForEach(ConversionSettings.SmartCompressionCodec.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.4)
    }
}
func getFormatIcon(for format: UTType) -> String {
    if format.isImageFormat {
        return "photo"
    } else if format.isVideoFormat {
        return "film"
    } else if format.isAudioFormat {
        return "waveform"
    } else if format.isPDFFormat {
        return "doc"
    } else {
        return "doc.fill"
    }
}

private func checkFormatCompatibility(input: UTType, output: UTType) -> Bool {
    // Define format categories
    let imageFormats: Set<UTType> = [.jpeg, .png, .tiff, .gif, .heic, .webP, .bmp]
    let videoFormats: Set<UTType> = [.mpeg4Movie, .quickTimeMovie, .avi]
    let audioFormats: Set<UTType> = [.mp3, .wav, .aiff, .m4a, .aac]
    
    // Enhanced cross-format conversion support
    switch (input, output) {
    // PDF conversions
    case (.pdf, _) where imageFormats.contains(output):
        return true
    case (_, .pdf) where imageFormats.contains(input):
        return true
        
    // Audio-Video conversions
    case (let i, let o) where i.conforms(to: .audio) && o.conforms(to: .audiovisualContent):
        return true
    case (let i, let o) where i.conforms(to: .audiovisualContent) && o.conforms(to: .audio):
        return true
        
    // Image-Video conversions
    case (let i, let o) where i.conforms(to: .image) && o.conforms(to: .audiovisualContent):
        return true
    case (let i, let o) where i.conforms(to: .audiovisualContent) && o.conforms(to: .image):
        return true
        
    // Image sequence to video
    case (let i, let o) where imageFormats.contains(i) && videoFormats.contains(o):
        return true
        
    // Video to image sequence
    case (let i, let o) where videoFormats.contains(i) && imageFormats.contains(o):
        return true
        
    // Audio visualization
    case (let i, let o) where audioFormats.contains(i) && (videoFormats.contains(o) || imageFormats.contains(o)):
        return true
        
    // Same category conversions
    case (let i, let o) where i.conforms(to: .image) && o.conforms(to: .image):
        return true
    case (let i, let o) where i.conforms(to: .audio) && o.conforms(to: .audio):
        return true
    case (let i, let o) where i.conforms(to: .audiovisualContent) && o.conforms(to: .audiovisualContent):
        return true
        
    default:
        return false
    }
}
