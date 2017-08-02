//
//  ViewController.swift
//  RectCapture
//
//  Created by Ben Scheirman on 6/27/17.
//  Copyright © 2017 NSScreencast. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage

class CaptureViewController: UIViewController {
    
    // MARK: - Properties
    
    lazy var boxLayer: CALayer = {
        let layer = CALayer()
        layer.borderColor = UIColor.red.cgColor
        layer.backgroundColor = UIColor.clear.cgColor
        layer.borderWidth = 4
        layer.cornerRadius = 8
        layer.isOpaque = false
        layer.opacity = 0
        self.view.layer.addSublayer(layer)
        return layer
    }()
    
    var hideBoxTimer: Timer?
    
    lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    let sampleBufferQueue = DispatchQueue.global(qos: .userInteractive)
    
    let ciContext = CIContext()
    
    lazy var rectDetector: CIDetector = {
        return CIDetector(ofType: CIDetectorTypeRectangle,
                          context: self.ciContext,
                          options: [CIDetectorAccuracy : CIDetectorAccuracyHigh])!
    }()
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            setupCaptureSession()
        } else {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (authorized) in
                DispatchQueue.main.async {
                    if authorized {
                        self.setupCaptureSession()
                    }
                }
            })
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.bounds = view.frame
    }
    
    // MARK: - Rotation
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait]
    }
    
    // MARK: - Camera Capture
    
    private func findCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInDualCamera,
            .builtInTelephotoCamera,
            .builtInWideAngleCamera
        ]
        
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                         mediaType: .video,
                                                         position: .back)
        
        return discovery.devices.first
    }
    
    private func setupCaptureSession() {
        guard captureSession.inputs.isEmpty else { return }
        guard let camera = findCamera() else {
            print("No camera found")
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(cameraInput)
            
            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.frame = view.bounds
            preview.backgroundColor = UIColor.black.cgColor
            preview.videoGravity = .resizeAspect
            view.layer.addSublayer(preview)
            self.previewLayer = preview
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            
            captureSession.addOutput(output)
            
            captureSession.startRunning()
            
        } catch let e {
            print("Error creating capture session: \(e)")
            return
        }
    }
    
    private func displayRect(rect: CGRect) {
        /*
             -------------
             ---(layer)---
             ---(preview)-
             ---(rect)----
             ^
         */
        hideBoxTimer?.invalidate()
        boxLayer.frame = rect
        boxLayer.opacity = 1
        
        hideBoxTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { (timer) in
            self.boxLayer.opacity = 0
            timer.invalidate()
        })
    }
}

extension CaptureViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let image = CIImage(cvImageBuffer: imageBuffer)
        for feature in rectDetector.features(in: image, options: nil) {
            guard let rectFeature = feature as? CIRectangleFeature else { continue }
            
            let imageWidth = image.extent.height
            let imageHeight = image.extent.width
            
            DispatchQueue.main.sync {
                let imageScale = min(view.frame.size.width / imageWidth,
                                     view.frame.size.height / imageHeight)
                let origin = CGPoint(x: rectFeature.topLeft.y * imageScale - rectFeature.bounds.size.height * imageScale,
                                     y: rectFeature.topLeft.x * imageScale)
                let size = CGSize(width: rectFeature.bounds.size.height * imageScale,
                                  height: rectFeature.bounds.size.width * imageScale)
                
                let rect = CGRect(origin: origin, size: size)
                self.displayRect(rect: rect)
            }
        }
    }
}
