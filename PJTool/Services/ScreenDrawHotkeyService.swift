//
//  ScreenDrawHotkeyService.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import AppKit
import Carbon
import Foundation

enum ScreenDrawHotkeyAction {
    case selectColor(DrawColorPreset)
    case selectTool(ScreenDrawTool)
    case clearCanvas
    case hideOverlay
    case showOverlay
    case disableCanvas
    case enableCanvas
}

final class ScreenDrawHotkeyService {
    var onAction: ((ScreenDrawHotkeyAction) -> Void)?
    var shouldHandleAction: ((ScreenDrawHotkeyAction) -> Bool)?

    private var globalHotKeyRefs: [EventHotKeyRef?] = []
    private var registeredHotkeyIDs: Set<Int> = []
    private var globalHotKeyEnabled = false
    private var localMonitor: Any?
    private var globalFallbackMonitor: Any?
    private var hotKeyEventHandlerRef: EventHandlerRef?
    private var hotKeyEventHandlerUPP: EventHandlerUPP?
    private var lastDispatchedActionAt: CFAbsoluteTime = 0
    private var lastDispatchedActionID: Int?

    func start() -> Bool {
        stop()

        let isCarbonHandlerReady = installHotKeyEventHandler()
        if isCarbonHandlerReady {
            globalHotKeyEnabled = registerGlobalHotkeys()
        } else {
            globalHotKeyEnabled = false
        }
        installMonitors(includeGlobalFallback: true)
        return globalHotKeyEnabled
    }

    func stop() {
        unregisterGlobalHotkeys()
        removeMonitors()
        removeHotKeyEventHandler()
        globalHotKeyEnabled = false
        registeredHotkeyIDs.removeAll()
    }

    private func registerGlobalHotkeys() -> Bool {
        var refs: [EventHotKeyRef?] = []
        registeredHotkeyIDs.removeAll()
        for descriptor in ScreenDrawHotkeyConstants.descriptors {
            var ref: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: ScreenDrawHotkeyConstants.signature, id: UInt32(descriptor.id))
            let status = RegisterEventHotKey(
                UInt32(descriptor.keyCode),
                descriptor.modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr {
                refs.append(ref)
                registeredHotkeyIDs.insert(descriptor.id)
            }
        }
        globalHotKeyRefs = refs
        return !registeredHotkeyIDs.isEmpty
    }

    private func installHotKeyEventHandler() -> Bool {
        guard hotKeyEventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            let service = Unmanaged<ScreenDrawHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            service.handleCarbonHotKeyPressed(eventRef)
            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &hotKeyEventHandlerRef
        )
        if status == noErr {
            hotKeyEventHandlerUPP = handler
            return true
        }
        hotKeyEventHandlerRef = nil
        hotKeyEventHandlerUPP = nil
        return false
    }

    private func removeHotKeyEventHandler() {
        if let hotKeyEventHandlerRef {
            RemoveEventHandler(hotKeyEventHandlerRef)
            self.hotKeyEventHandlerRef = nil
        }
        hotKeyEventHandlerUPP = nil
    }

    private func unregisterGlobalHotkeys() {
        for ref in globalHotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        globalHotKeyRefs = []
    }

    private func installMonitors(includeGlobalFallback: Bool) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if let action = self.action(for: event, skipRegisteredHotkeys: false),
               self.shouldProcess(action) {
                self.onAction?(action)
                return nil
            }
            return event
        }

        if includeGlobalFallback {
            globalFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard
                    let self,
                    let action = self.action(for: event, skipRegisteredHotkeys: true),
                    self.shouldProcess(action)
                else { return }
                self.onAction?(action)
            }
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalFallbackMonitor {
            NSEvent.removeMonitor(globalFallbackMonitor)
            self.globalFallbackMonitor = nil
        }
    }

    private func action(for event: NSEvent, skipRegisteredHotkeys: Bool) -> ScreenDrawHotkeyAction? {
        guard event.type == .keyDown else { return nil }
        guard let descriptor = descriptor(for: event) else {
            return nil
        }
        if skipRegisteredHotkeys, registeredHotkeyIDs.contains(descriptor.id) {
            return nil
        }
        return descriptor.action
    }

    private func isMatch(_ modifiers: NSEvent.ModifierFlags, required: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control]
        return modifiers.intersection(relevant) == required.intersection(relevant)
    }

    private func sanitizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift, .capsLock])
    }

    private func descriptor(for event: NSEvent) -> HotkeyDescriptor? {
        let keyCode = Int16(event.keyCode)
        let modifiers = sanitizedModifiers(event.modifierFlags)

        return ScreenDrawHotkeyConstants.descriptors.first { descriptor in
            guard descriptor.keyCode == keyCode else { return false }
            let required = requiredFlags(for: descriptor.modifiers)
            return isMatch(modifiers, required: required)
        }
    }

    private func requiredFlags(for carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var required: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            required.insert(.command)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            required.insert(.control)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            required.insert(.option)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            required.insert(.shift)
        }
        return required
    }

    private func shouldProcess(_ action: ScreenDrawHotkeyAction) -> Bool {
        shouldHandleAction?(action) ?? true
    }

    private func handleCarbonHotKeyPressed(_ eventRef: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }

        guard
            let descriptor = ScreenDrawHotkeyConstants.descriptors.first(where: { $0.id == Int(hotKeyID.id) }),
            shouldProcess(descriptor.action)
        else { return }

        if isLikelyDuplicateDispatch(for: descriptor.id) {
            return
        }
        onAction?(descriptor.action)
    }

    func handleEvent(_ event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 6 else { return }

        let data = event.data1
        let hotkeyID = Int((data & 0xFFFF0000) >> 16)

        guard let descriptor = ScreenDrawHotkeyConstants.descriptors.first(where: { $0.id == hotkeyID }) else {
            return
        }
        if isLikelyDuplicateDispatch(for: descriptor.id) {
            return
        }
        onAction?(descriptor.action)
    }

    private func isLikelyDuplicateDispatch(for id: Int) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        defer {
            lastDispatchedActionAt = now
            lastDispatchedActionID = id
        }
        guard lastDispatchedActionID == id else { return false }
        return now - lastDispatchedActionAt < 0.08
    }
}

private enum ScreenDrawHotkeyConstants {
    static let signature: OSType = 0x53445257 // 'SDRW'
    static let descriptors: [HotkeyDescriptor] = [
        HotkeyDescriptor(id: 1, keyCode: Int16(kVK_ANSI_1), modifiers: UInt32(controlKey | optionKey), action: .selectColor(.one)),
        HotkeyDescriptor(id: 2, keyCode: Int16(kVK_ANSI_2), modifiers: UInt32(controlKey | optionKey), action: .selectColor(.two)),
        HotkeyDescriptor(id: 3, keyCode: Int16(kVK_ANSI_3), modifiers: UInt32(controlKey | optionKey), action: .selectColor(.three)),
        HotkeyDescriptor(id: 4, keyCode: Int16(kVK_ANSI_4), modifiers: UInt32(controlKey | optionKey), action: .selectColor(.four)),
        HotkeyDescriptor(id: 5, keyCode: Int16(kVK_ANSI_5), modifiers: UInt32(controlKey | optionKey), action: .selectColor(.five)),
        HotkeyDescriptor(id: 6, keyCode: Int16(kVK_ANSI_1), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.line)),
        HotkeyDescriptor(id: 7, keyCode: Int16(kVK_ANSI_2), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.arrow)),
        HotkeyDescriptor(id: 8, keyCode: Int16(kVK_ANSI_3), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.rectangle)),
        HotkeyDescriptor(id: 9, keyCode: Int16(kVK_ANSI_4), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.ellipse)),
        HotkeyDescriptor(id: 10, keyCode: Int16(kVK_ANSI_5), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.cross)),
        HotkeyDescriptor(id: 11, keyCode: Int16(kVK_ANSI_6), modifiers: UInt32(cmdKey | optionKey), action: .selectTool(.check)),
        HotkeyDescriptor(id: 12, keyCode: Int16(kVK_ANSI_C), modifiers: UInt32(cmdKey | optionKey), action: .clearCanvas),
        HotkeyDescriptor(id: 13, keyCode: Int16(kVK_ANSI_H), modifiers: UInt32(cmdKey | optionKey), action: .hideOverlay),
        HotkeyDescriptor(id: 14, keyCode: Int16(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey), action: .showOverlay),
        HotkeyDescriptor(id: 15, keyCode: Int16(kVK_ANSI_D), modifiers: UInt32(cmdKey | optionKey), action: .disableCanvas),
        HotkeyDescriptor(id: 16, keyCode: Int16(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey), action: .enableCanvas)
    ]
}

private struct HotkeyDescriptor {
    let id: Int
    let keyCode: Int16
    let modifiers: UInt32
    let action: ScreenDrawHotkeyAction
}
