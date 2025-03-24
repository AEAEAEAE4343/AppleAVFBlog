//
//  AppDelegate.swift
//  Example Windows VM in AVF
//  This project is provided under the MIT License
//
//  Created by Anis Errais on 19/03/2025.
//

import SwiftUI
import Virtualization

struct VMView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine
    
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let vmView = VZVirtualMachineView()
        vmView.virtualMachine = virtualMachine
        print("VM Attached!")
        print("VM state: \(virtualMachine.state)")
        return vmView
    }
    
    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {}
}

@main
struct MyApp: App {
    let displayWidth = 1024;
    let displayHeight = 768;
    
    func createVM() async -> VZVirtualMachine {
        // Basic VM settings
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = 4
        configuration.memorySize = 4 * 1024 * 1024 * 1024 // 8 GiB
        
        // Standard UEFI bootloader
        let bootLoader = VZEFIBootLoader()
        // NVRAM
        bootLoader.variableStore = try! VZEFIVariableStore(creatingVariableStoreAt: URL(string: "file:///Users/aniserrais/Desktop/vmefi.bin")!, options: VZEFIVariableStore.InitializationOptions.allowOverwrite)
        configuration.bootLoader = bootLoader
        
        /*
         * Disabled for Windows
         *
         
        // Graphics
        let graphicsOut = VZVirtioGraphicsScanoutConfiguration(widthInPixels: displayWidth, heightInPixels: displayHeight)
        let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
        graphicsDevice.scanouts = [graphicsOut]
        //configuration.graphicsDevices = [graphicsDevice]
        
        // Keyboard
        configuration.keyboards = [VZUSBKeyboardConfiguration()]
        // Mouse
        configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
         */
        
        // Network (NAT)
        let networkAttachment = VZNATNetworkDeviceAttachment()
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = networkAttachment
        configuration.networkDevices = [networkDevice]
        
        // Mounted image or physical disk
        let hddFile = FileHandle(forUpdatingAtPath: "/dev/disk4")!
        let hdd = try! VZDiskBlockDeviceStorageDeviceAttachment(fileHandle: hddFile, readOnly: false, synchronizationMode: VZDiskSynchronizationMode.full)
        
        // Virtual Disk Image
        //let hdd = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: "/Users/aniserrais/Desktop/win10.img"), readOnly: false, cachingMode: VZDiskImageCachingMode.automatic, synchronizationMode: VZDiskImageSynchronizationMode.full)
        configuration.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: hdd)]
        
        try! configuration.validate()
        print("VM Valid!")
        return VZVirtualMachine(configuration: configuration)
    }
    
    @State var vm: VZVirtualMachine?
    @FocusState var vmFocus: Bool

    var body: some Scene {
        
        WindowGroup {
            if let vm = vm {
                VMView(virtualMachine: vm)
                    .focused($vmFocus)
                    .frame(width: CGFloat(displayWidth), height: CGFloat(displayHeight))
                    .onDisappear(perform: { Task {
                        if (vm.canStop) {
                            try! await vm.stop()
                        }
                        print("VM Stopped!")
                        print("VM state: \(vm.state)")
                        self.vm = nil
                    } })
            } else {
                Text("Starting VM...")
                    .onAppear {
                        Task {
                            let machine = await createVM()
                            vm = machine
                            try! await machine.start()
                            vmFocus = true
                        }
                    }
            }
        }
        .windowResizability(WindowResizability.contentSize)
    }
}
