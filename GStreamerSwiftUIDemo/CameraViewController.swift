//
//  CameraViewController.swift
//  GStreamerSwiftUIDemo
//
//  Created by Raktim Bora on 19.06.23.
//

import Foundation
import UIKit
import Dispatch
import SwiftUI
import AVFoundation


@objc class CameraViewController: NSObject, GStreamerBackendProtocol, ObservableObject{
    
    var gstBackend:GStreamerBackend?
    var camUIView:UIView
    @Published var gStreamerInitializationStatus:Bool = false
    @Published var messageFromGstBackend:String?
    
    init(camUIView:UIView) {
        self.camUIView = camUIView
    }
    
    func initBackend(){
        self.requestCameraPermission()
        self.requestMicrophonePermission()

        self.gstBackend = GStreamerBackend(self, videoView: self.camUIView)
        let queue = DispatchQueue(label: "run_app_q")
        queue.async{
            self.gstBackend?.run_app_pipeline_threaded()
        }
        return
    }
    
    func play(){
        if gstBackend == nil{
            self.initBackend()
        }
        self.gstBackend!.play()
    }
    
    func pause(){
        self.gstBackend!.pause()
    }
    
    func requestCameraPermission() {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
          // The user has previously granted access to the camera.
          break
          
        case .notDetermined:
          // The user has not yet been asked for camera access.
          AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
              // Access granted.
            } else {
              // Access denied.
            }
          }
          
        case .denied, .restricted:
          // The user has previously denied access or it's restricted.
          break
          
        @unknown default:
          fatalError()
      }
    }
    
    func requestMicrophonePermission() {
      switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
          // The user has previously granted access to the microphone.
          break
          
        case .denied:
          // The user has previously denied access.
          break
          
        case .undetermined:
          // The user has not yet been asked for microphone access.
          AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
              // Access granted.
            } else {
              // Access denied.
            }
          }
          
        @unknown default:
          fatalError()
      }
    }
    
    @objc func gStreamerInitialized() {
      DispatchQueue.main.async {
        self.gStreamerInitializationStatus = true
      }
    }
    
    @objc func gstreamerSetUIMessageWithMessage(message: String) {
      DispatchQueue.main.async {
        self.messageFromGstBackend = message
      }
    }
    
    
}
