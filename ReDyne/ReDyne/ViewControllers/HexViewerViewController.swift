import UIKit

class HexViewerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {
    
    // MARK: - UI Elements
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(HexViewerCell.self, forCellReuseIdentifier: "HexViewerCell")
        table.separatorStyle = .singleLine
        table.backgroundColor = Constants.Colors.primaryBackground
        table.allowsSelection = true
        return table
    }()
    
    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search address (0x...)"
        search.delegate = self
        search.searchBarStyle = .minimal
        return search
    }()
    
    private lazy var filterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Filters", for: .normal)
        button.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"), for: .normal)
        button.addTarget(self, action: #selector(showFilters), for: .touchUpInside)
        return button
    }()
    
    private lazy var goToButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Go To", for: .normal)
        button.setImage(UIImage(systemName: "arrow.right.circle"), for: .normal)
        button.addTarget(self, action: #selector(showGoToMenu), for: .touchUpInside)
        return button
    }()
    
    private lazy var infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private lazy var annotationToggle: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = true
        toggle.addTarget(self, action: #selector(toggleAnnotations), for: .valueChanged)
        return toggle
    }()
    
    private lazy var annotationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Annotations"
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .label
        return label
    }()
    
    // MARK: - Properties
    
    private let fileURL: URL
    private var binaryData: Data?
    private var filteredData: Data?
    private var currentOffset: UInt64 = 0
    private let bytesPerRow = 16
    private var highlightedRange: Range<Int>?
    private var showAnnotations = true
    
    // Filter state
    private var activeFilters: Set<HexViewerFilter> = []
    private var visibleSections: Set<String> = []
    
    // Analysis data
    private let segments: [SegmentModel]
    private let sections: [SectionModel]
    private let functions: [FunctionModel]
    private let symbols: [SymbolModel]
    
    // MARK: - Initialization
    
    init(fileURL: URL, segments: [SegmentModel], sections: [SectionModel], functions: [FunctionModel], symbols: [SymbolModel]) {
        self.fileURL = fileURL
        self.segments = segments
        self.sections = sections
        self.functions = functions
        self.symbols = symbols
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Hex Viewer"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupNavigationBar()
        loadBinaryData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        let toolbar = UIStackView(arrangedSubviews: [filterButton, goToButton])
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.axis = .horizontal
        toolbar.spacing = Constants.UI.standardSpacing
        toolbar.distribution = .fillEqually
        
        let annotationStack = UIStackView(arrangedSubviews: [annotationLabel, annotationToggle])
        annotationStack.translatesAutoresizingMaskIntoConstraints = false
        annotationStack.axis = .horizontal
        annotationStack.spacing = Constants.UI.compactSpacing
        
        view.addSubview(searchBar)
        view.addSubview(toolbar)
        view.addSubview(annotationStack)
        view.addSubview(tableView)
        view.addSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            toolbar.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Constants.UI.compactSpacing),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            
            annotationStack.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: Constants.UI.compactSpacing),
            annotationStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            tableView.topAnchor.constraint(equalTo: annotationStack.bottomAnchor, constant: Constants.UI.compactSpacing),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: infoLabel.topAnchor),
            
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            infoLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.UI.compactSpacing),
            infoLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        updateInfoLabel()
    }
    
    private func setupNavigationBar() {
        let exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportHexDump)
        )
        
        let legendButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showLegend)
        )
        
        navigationItem.rightBarButtonItems = [exportButton, legendButton]
    }
    
    // MARK: - Data Loading
    
    private func loadBinaryData() {
        do {
            binaryData = try Data(contentsOf: fileURL)
            filteredData = binaryData
            updateInfoLabel()
            tableView.reloadData()
        } catch {
            showAlert(title: "Error", message: "Failed to load binary data: \(error.localizedDescription)")
        }
    }
    
    private func updateInfoLabel() {
        guard let data = filteredData else {
            infoLabel.text = "No data loaded"
            return
        }
        
        let totalBytes = data.count
        let displayedBytes = min(totalBytes, bytesPerRow * tableView.numberOfRows(inSection: 0))
        infoLabel.text = String(format: "Total: %@ | Displayed: %d bytes | Offset: 0x%llX",
                               Constants.formatBytes(Int64(totalBytes)),
                               displayedBytes,
                               currentOffset)
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let data = filteredData else { return 0 }
        return (data.count + bytesPerRow - 1) / bytesPerRow
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HexViewerCell", for: indexPath) as! HexViewerCell
        
        guard let data = filteredData else { return cell }
        
        let offset = indexPath.row * bytesPerRow
        let endOffset = min(offset + bytesPerRow, data.count)
        let rowData = data[offset..<endOffset]
        
        let address = currentOffset + UInt64(offset)
        let isHighlighted = highlightedRange?.contains(offset) ?? false
        
        // Find if this address is in a known section
        let sectionInfo = findSection(for: address)
        
        cell.configure(with: rowData, address: address, bytesPerRow: bytesPerRow, 
                      isHighlighted: isHighlighted, sectionName: showAnnotations ? sectionInfo?.sectionName : nil)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let offset = indexPath.row * bytesPerRow
        let address = currentOffset + UInt64(offset)
        
        showAddressDetails(address: address, offset: offset)
    }
    
    // MARK: - Annotation Control
    
    @objc private func toggleAnnotations() {
        showAnnotations = annotationToggle.isOn
        tableView.reloadData()
    }
    
    // MARK: - Helper Methods
    
    private func findSection(for address: UInt64) -> SectionModel? {
        return sections.first { section in
            address >= section.address && address < section.address + section.size
        }
    }
    
    private func findFunction(for address: UInt64) -> FunctionModel? {
        return functions.first { function in
            address >= function.startAddress && address <= function.endAddress
        }
    }
    
    private func findSymbol(for address: UInt64) -> SymbolModel? {
        return symbols.first { symbol in
            symbol.address == address
        }
    }
    
    private func showAddressDetails(address: UInt64, offset: Int) {
        var details = "Address: \(Constants.formatAddress(address))\n"
        details += "Offset: 0x\(String(format: "%08X", offset))\n\n"
        
        if let section = findSection(for: address) {
            details += "Section: \(section.segmentName).\(section.sectionName)\n"
        }
        
        if let function = findFunction(for: address) {
            details += "Function: \(function.name)\n"
            details += "Function Range: \(Constants.formatAddress(function.startAddress)) - \(Constants.formatAddress(function.endAddress))\n"
        }
        
        if let symbol = findSymbol(for: address) {
            details += "Symbol: \(symbol.name)\n"
            details += "Type: \(symbol.type)\n"
        }
        
        let alert = UIAlertController(title: "Address Details", message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
            UIPasteboard.general.string = Constants.formatAddress(address)
        })
        present(alert, animated: true)
    }
    
    @objc private func showLegend() {
        let legend = """
        Hex Viewer Legend
        
        📍 Address Column: Memory address in hexadecimal
        🔢 Hex Column: Raw byte values in hex
        📝 ASCII Column: Printable characters (. for non-printable)
        
        Annotations:
        • Section names show which section contains the data
        • Highlighted rows indicate current selection
        • Use "Go To" to navigate by address, function, or section
        
        Filters:
        • Show Code Sections: Display only executable code
        • Show Data Sections: Display only data sections
        
        Tips:
        • Long-press on a row for context menu
        • Use the search bar to jump to specific addresses
        • Export hex dump to text or binary format
        """
        
        let alert = UIAlertController(title: "Hex Viewer Help", message: legend, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Navigation Actions
    
    @objc private func showGoToMenu() {
        let alert = UIAlertController(title: "Go To", message: "Select navigation option", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Go to Address", style: .default) { [weak self] _ in
            self?.showGoToAddress()
        })
        
        alert.addAction(UIAlertAction(title: "Go to Function", style: .default) { [weak self] _ in
            self?.showGoToFunction()
        })
        
        alert.addAction(UIAlertAction(title: "Go to Section", style: .default) { [weak self] _ in
            self?.showGoToSection()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = goToButton
        }
        
        present(alert, animated: true)
    }
    
    private func showGoToAddress() {
        let alert = UIAlertController(title: "Go to Address", message: "Enter hexadecimal address (e.g., 0x1000)", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "0x..."
            textField.keyboardType = .asciiCapable
        }
        
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let text = alert?.textFields?.first?.text else { return }
            
            if let address = self.parseAddress(text) {
                self.scrollToAddress(address)
            } else {
                self.showAlert(title: "Invalid Address", message: "Please enter a valid hexadecimal address (e.g., 0x1000)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showGoToFunction() {
        let functionNames = functions.map { $0.name }
        
        if functionNames.isEmpty {
            showAlert(title: "No Functions", message: "No functions found in this binary")
            return
        }
        
        let functionPickerVC = FunctionPickerViewController(functions: functions) { [weak self] selectedFunction in
            self?.scrollToAddress(selectedFunction.startAddress)
        }
        
        let navController = UINavigationController(rootViewController: functionPickerVC)
        present(navController, animated: true)
    }
    
    private func showGoToSection() {
        let alert = UIAlertController(title: "Go to Section", message: "Select a section", preferredStyle: .actionSheet)
        
        for section in sections {
            let title = "\(section.segmentName).\(section.sectionName) (\(Constants.formatAddress(section.address)))"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.scrollToAddress(section.address)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = goToButton
        }
        
        present(alert, animated: true)
    }
    
    private func parseAddress(_ text: String) -> UInt64? {
        var cleanText = text.trimmingCharacters(in: .whitespaces)
        
        if cleanText.hasPrefix("0x") || cleanText.hasPrefix("0X") {
            cleanText = String(cleanText.dropFirst(2))
        }
        
        return UInt64(cleanText, radix: 16)
    }
    
    func scrollToAddress(_ address: UInt64) {
        guard let data = filteredData else { return }
        
        // Calculate offset from current base address
        if address < currentOffset {
            showAlert(title: "Address Out of Range", message: "Address is before the start of the file")
            return
        }
        
        let offset = Int(address - currentOffset)
        
        if offset >= data.count {
            showAlert(title: "Address Out of Range", message: "Address is beyond the end of the file")
            return
        }
        
        let row = offset / bytesPerRow
        let indexPath = IndexPath(row: row, section: 0)
        
        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        
        // Highlight the row
        let byteOffset = offset % bytesPerRow
        highlightedRange = offset..<(offset + 1)
        tableView.reloadRows(at: [indexPath], with: .none)
        
        // Show success message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let toast = UILabel()
            toast.text = "Jumped to \(Constants.formatAddress(address))"
            toast.backgroundColor = Constants.Colors.successColor.withAlphaComponent(0.9)
            toast.textColor = .white
            toast.textAlignment = .center
            toast.font = .systemFont(ofSize: 14, weight: .medium)
            toast.frame = CGRect(x: 20, y: self.view.safeAreaInsets.top + 60, 
                               width: self.view.bounds.width - 40, height: 44)
            toast.layer.cornerRadius = 8
            toast.clipsToBounds = true
            self.view.addSubview(toast)
            
            UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseOut) {
                toast.alpha = 0
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Filter Actions
    
    @objc private func showFilters() {
        let alert = UIAlertController(title: "Hex Viewer Filters", message: "Select data to display", preferredStyle: .actionSheet)
        
        // Filter by data type
        alert.addAction(UIAlertAction(title: "Show Code Sections", style: .default) { [weak self] _ in
            self?.filterByType(.code)
        })
        
        alert.addAction(UIAlertAction(title: "Show Data Sections", style: .default) { [weak self] _ in
            self?.filterByType(.data)
        })
        
        alert.addAction(UIAlertAction(title: "Show All", style: .default) { [weak self] _ in
            self?.clearFilters()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = filterButton
        }
        
        present(alert, animated: true)
    }
    
    private func filterByType(_ filterType: HexViewerFilter) {
        activeFilters.insert(filterType)
        applyFilters()
    }
    
    private func clearFilters() {
        activeFilters.removeAll()
        filteredData = binaryData
        tableView.reloadData()
        updateInfoLabel()
    }
    
    private func applyFilters() {
        // For now, just reload without filtering
        // In a production implementation, this would filter the data based on sections
        filteredData = binaryData
        tableView.reloadData()
        updateInfoLabel()
    }
    
    // MARK: - Export
    
    @objc private func exportHexDump() {
        guard let data = filteredData else { return }
        
        let alert = UIAlertController(title: "Export Hex Dump", message: "Choose export format", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Text Format", style: .default) { [weak self] _ in
            self?.performExport(data: data, format: .text)
        })
        
        alert.addAction(UIAlertAction(title: "Binary Format", style: .default) { [weak self] _ in
            self?.performExport(data: data, format: .binary)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
    
    private func performExport(data: Data, format: HexExportFormat) {
        let exportData: Data
        let filename: String
        
        switch format {
        case .text:
            let hexDump = generateHexDump(data: data)
            exportData = hexDump.data(using: .utf8) ?? Data()
            filename = "hexdump.txt"
        case .binary:
            exportData = data
            filename = "binary.bin"
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try exportData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItem
            }
            
            present(activityVC, animated: true)
        } catch {
            showAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
    
    private func generateHexDump(data: Data) -> String {
        var dump = ""
        
        for row in 0..<((data.count + bytesPerRow - 1) / bytesPerRow) {
            let offset = row * bytesPerRow
            let endOffset = min(offset + bytesPerRow, data.count)
            let rowData = data[offset..<endOffset]
            
            let address = currentOffset + UInt64(offset)
            dump += String(format: "%016llX  ", address)
            
            // Hex bytes
            for byte in rowData {
                dump += String(format: "%02X ", byte)
            }
            
            // Padding
            for _ in rowData.count..<bytesPerRow {
                dump += "   "
            }
            
            dump += " |"
            
            // ASCII representation
            for byte in rowData {
                if byte >= 32 && byte < 127 {
                    dump += String(UnicodeScalar(byte))
                } else {
                    dump += "."
                }
            }
            
            dump += "|\n"
        }
        
        return dump
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        
        guard let text = searchBar.text, !text.isEmpty else { return }
        
        if let address = parseAddress(text) {
            scrollToAddress(address)
        }
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
    }
    
    // MARK: - Alerts
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Hex Viewer Cell

class HexViewerCell: UITableViewCell {
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = Constants.Colors.addressColor
        return label
    }()
    
    private let hexLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private let asciiLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let sectionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 9, weight: .regular)
        label.textColor = Constants.Colors.accentColor
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(addressLabel)
        contentView.addSubview(hexLabel)
        contentView.addSubview(asciiLabel)
        contentView.addSubview(sectionLabel)
        
        NSLayoutConstraint.activate([
            addressLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            addressLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            addressLabel.widthAnchor.constraint(equalToConstant: 140),
            
            hexLabel.leadingAnchor.constraint(equalTo: addressLabel.trailingAnchor, constant: 8),
            hexLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            hexLabel.trailingAnchor.constraint(equalTo: asciiLabel.leadingAnchor, constant: -8),
            
            asciiLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            asciiLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            asciiLabel.widthAnchor.constraint(equalToConstant: 140),
            
            sectionLabel.leadingAnchor.constraint(equalTo: addressLabel.leadingAnchor),
            sectionLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 2),
            sectionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }
    
    func configure(with data: Data, address: UInt64, bytesPerRow: Int, isHighlighted: Bool, sectionName: String?) {
        // Address
        addressLabel.text = String(format: "%016llX", address)
        
        // Hex bytes
        var hexString = ""
        for (index, byte) in data.enumerated() {
            hexString += String(format: "%02X", byte)
            if (index + 1) % 4 == 0 && index < data.count - 1 {
                hexString += " "
            } else if index < data.count - 1 {
                hexString += " "
            }
        }
        hexLabel.text = hexString
        
        // ASCII representation
        var asciiString = ""
        for byte in data {
            if byte >= 32 && byte < 127 {
                asciiString += String(UnicodeScalar(byte))
            } else {
                asciiString += "."
            }
        }
        asciiLabel.text = asciiString
        
        // Section name
        if let section = sectionName {
            sectionLabel.text = section
            sectionLabel.isHidden = false
        } else {
            sectionLabel.isHidden = true
        }
        
        // Highlight if needed
        if isHighlighted {
            contentView.backgroundColor = Constants.Colors.accentColor.withAlphaComponent(0.2)
        } else {
            contentView.backgroundColor = Constants.Colors.primaryBackground
        }
    }
}

// MARK: - Supporting Types

enum HexViewerFilter {
    case code
    case data
    case strings
}

enum HexExportFormat {
    case text
    case binary
}

// MARK: - Function Picker

class FunctionPickerViewController: UITableViewController, UISearchBarDelegate {
    
    private let functions: [FunctionModel]
    private var filteredFunctions: [FunctionModel]
    private let onSelect: (FunctionModel) -> Void
    
    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.placeholder = "Search functions..."
        search.delegate = self
        return search
    }()
    
    init(functions: [FunctionModel], onSelect: @escaping (FunctionModel) -> Void) {
        self.functions = functions
        self.filteredFunctions = functions
        self.onSelect = onSelect
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Select Function"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.tableHeaderView = searchBar
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFunctions.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let function = filteredFunctions[indexPath.row]
        
        cell.textLabel?.text = function.name
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        cell.detailTextLabel?.text = Constants.formatAddress(function.startAddress)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let function = filteredFunctions[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onSelect(function)
        }
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            filteredFunctions = functions
        } else {
            filteredFunctions = functions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        tableView.reloadData()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        filteredFunctions = functions
        tableView.reloadData()
    }
}
