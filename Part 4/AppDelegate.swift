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
    // These values only affect window size
    // Unfortunately, the Windows driver for VirtGL does not support modesetting
    let displayWidth = 1024;
    let displayHeight = 768;
    
    func createVM() async -> VZVirtualMachine {
        // Basic VM settings
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = 4
        configuration.memorySize = 8 * 1024 * 1024 * 1024 // 8 GiB

        // Standard UEFI bootloader
        let bootLoader = VZEFIBootLoader()
        // NVRAM
        bootLoader.variableStore = try! VZEFIVariableStore(creatingVariableStoreAt: URL(string: "file:///Users/aniserrais/Desktop/vmefi.bin")!, options: VZEFIVariableStore.InitializationOptions.allowOverwrite)
        configuration.bootLoader = bootLoader
        
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
        
        /*
         * Newly added since part 3
         */
        
        // Graphics
        // Only provides display output
        // System runs much faster in RDP using software rendering!
        // There is however active development on getting 3D aceleration working:
        // https://github.com/virtio-win/kvm-guest-drivers-windows/pull/943
        let graphicsOut = VZVirtioGraphicsScanoutConfiguration(widthInPixels: displayWidth, heightInPixels: displayHeight)
        let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
        graphicsDevice.scanouts = [graphicsOut]
        configuration.graphicsDevices = [graphicsDevice]
        
        // Keyboard
        configuration.keyboards = [VZUSBKeyboardConfiguration()]
        // Mouse
        configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        
        // Sound
        // Unsupported in Windows
        /*
        let audioDevice = VZVirtioSoundDeviceConfiguration()
        let audioInput = VZVirtioSoundDeviceInputStreamConfiguration()
        audioInput.source = VZHostAudioInputStreamSource()
        let audioOutput = VZVirtioSoundDeviceOutputStreamConfiguration()
        audioOutput.sink = VZHostAudioOutputStreamSink()
        audioDevice.streams = [audioInput, audioOutput]
        configuration.audioDevices = [audioDevice]
         */
        
        // Shared clipboard
        // Oddly enough, unsupported on my host
        let spiceAttachment = VZSpiceAgentPortAttachment()
        spiceAttachment.sharesClipboard = true
        let spicePort = VZVirtioConsolePortConfiguration()
        spicePort.attachment = spiceAttachment
        let spiceDevice = VZVirtioConsoleDeviceConfiguration()
        spiceDevice.ports[0] = spicePort
        configuration.consoleDevices = [spiceDevice]
        
        // Shared directory
        let sharedDir = VZSharedDirectory(url: URL(fileURLWithPath: "/Users/aniserrais/"), readOnly: false)
        let sharedDirDevice = VZVirtioFileSystemDeviceConfiguration(tag: "homedir")
        sharedDirDevice.share = VZSingleDirectoryShare(directory: sharedDir)
        configuration.directorySharingDevices = [sharedDirDevice]
        
        // Dynamic memory
        let memoryBalloon = VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        configuration.memoryBalloonDevices = [memoryBalloon]
        
        try! configuration.validate()
        print("VM Valid!")
        let vm = VZVirtualMachine(configuration: configuration)
        return vm
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
                            if let virtioBalloon = machine.memoryBalloonDevices.first as? VZVirtioTraditionalMemoryBalloonDevice {
                                // You can change this value even while the VM is running to reallocate memory for the host
                                virtioBalloon.targetVirtualMachineMemorySize = 6 * 1024 * 1024 * 1024
                            } else {
                                print("Casting failed")
                            }
                            vmFocus = true
                        }
                    }
            }
        }
        .windowResizability(WindowResizability.contentSize)
    }
}
