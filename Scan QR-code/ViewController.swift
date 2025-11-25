//
//  ViewController.swift
//  Scan QR-code
//
//  Created by Siarhei Lukyanau on 25.11.25.
//

import UIKit
import AVFoundation
import AudioToolbox

final class ViewController: UIViewController {
    
    private let previewView = UIView()
    private let resultLabel: UILabel = {
        let label = UILabel()
        label.text = "Point the camera at a QR code"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }()
    private let scanButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Start Scanning"
        let button = UIButton(configuration: configuration)
        return button
    }()
    
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isReadyToScan = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        scanButton.addTarget(self, action: #selector(startScanning), for: .touchUpInside)
        checkCameraAuthorization()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }
    
    private func setupLayout() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(previewView)
        view.addSubview(resultLabel)
        view.addSubview(scanButton)
        
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor),
            
            resultLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 24),
            resultLabel.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            
            scanButton.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 24),
            scanButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureCaptureSession() : self?.handleCameraAccessDenied()
                }
            }
        case .denied, .restricted:
            handleCameraAccessDenied()
        @unknown default:
            handleCameraAccessDenied()
        }
    }
    
    private func configureCaptureSession() {
        guard !captureSession.isRunning else { return }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        do {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .back) else {
                updateResult("No suitable camera available.")
                captureSession.commitConfiguration()
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }
        } catch {
            updateResult("Failed to set up camera: \(error.localizedDescription)")
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.commitConfiguration()
        setupPreviewLayer()
        isReadyToScan = true
        startSessionIfNeeded()
    }
    
    private func setupPreviewLayer() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
    
    @objc
    private func startScanning() {
        guard isReadyToScan else {
            updateResult("Camera is not ready yet.")
            return
        }
        if !captureSession.isRunning {
            startSessionIfNeeded()
        }
        resultLabel.text = "Scanning..."
    }
    
    private func startSessionIfNeeded() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    private func stopSession() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    private func handleCameraAccessDenied() {
        updateResult("Camera access is required. Update permissions in Settings.")
        scanButton.isEnabled = false
    }
    
    private func updateResult(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.resultLabel.text = text
        }
    }
}

extension ViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                       didOutput metadataObjects: [AVMetadataObject],
                       from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let value = metadataObject.stringValue else {
            return
        }
        
        updateResult(value)
        stopSession()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        scanButton.configuration?.title = "Scan Again"
    }
}

