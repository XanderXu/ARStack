//
//  ViewController.swift
//  ARStack
//
//  Created by CoderXu on 2017/10/14.
//  Copyright © 2017年 XanderXu. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet weak var sessionInfoLabel: UILabel!
    
    @IBOutlet weak var playButton: UIButton!
    
    @IBOutlet weak var restartButton: UIButton!
    weak var baseNode: SCNNode?
    weak var planeNode: SCNNode?
    var updateCount: NSInteger = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        playButton.isHidden = true
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        // Create a new scene
        let scene = SCNScene()
        // Set the scene to the view
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError("""
                ARKit is not available on this device. For apps that require ARKit
                for core functionality, use the `arkit` key in the key in the
                `UIRequiredDeviceCapabilities` section of the Info.plist to prevent
                the app from installing. (If the app can't be installed, this error
                can't be triggered in a production scenario.)
                In apps where AR is an additive feature, use `isSupported` to
                determine whether to show UI for launching AR experiences.
            """) // For details, see https://developer.apple.com/documentation/arkit
        }
        //重置界面,参数,追踪配置
        resetAll()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    @IBAction func playButtonClick(_ sender: UIButton) {
        //0.隐藏按钮
        playButton.isHidden = true
        sessionInfoLabel.isHidden = true
        //1.停止平面检测
        stopTracking()
        //2.不显示辅助点
        sceneView.debugOptions = []
        //3.更改平面的透明度和颜色
        planeNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        planeNode?.opacity = 1
        //4.载入游戏场景
    }
    @IBAction func restartButtonClick(_ sender: UIButton) {
        resetAll()
    }
    
}
// MARK:- 私有方法
extension ViewController {
    
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // 更新UI,反馈AR状态.
        let message: String
        print("status")
        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // 未检测到平面
            message = "移动设备来探测水平面."
            
        case .normal:
            // 平面可见,跟踪正常,无需反馈
            message = ""
            
        case .notAvailable:
            message = "无法追踪."
            
        case .limited(.excessiveMotion):
            message = "追踪受限-请缓慢移动设备."
            
        case .limited(.insufficientFeatures):
            message = "追踪受限-将设备对准平面上的可见花纹区域,或改善光照条件."
            
        case .limited(.initializing):
            message = "初始化AR中."
            
        }
        print(message)
        sessionInfoLabel.text = message
        sessionInfoLabel.isHidden = message.isEmpty
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    private func stopTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .init(rawValue: 0)
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration)
    }
    
    private func resetAll() {
        //0.显示按钮
        playButton.isHidden = true
        sessionInfoLabel.isHidden = false
        //1.重置更新次数
        updateCount = 0
        //2.重置平面检测配置,重启检测
        resetTracking()
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
    }
}

extension ViewController:ARSCNViewDelegate {
    // MARK: - ARSCNViewDelegate
    
    // 识别到新的锚点后,添加什么样的node.不实现该代理的话,会添加一个默认的空的node
    // ARKit会自动管理这个node的可见性及transform等属性等,所以一般把自己要显示的内容添加在这个node下面作为子节点
    //    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
    //
    //        let node = SCNNode()
    //
    //        return node
    //    }
    
    // node添加到新的锚点上之后(一般在这个方法中添加几何体节点,作为node的子节点)
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        //1.获取捕捉到的平地锚点,只识别并添加一个平面
        if let planeAnchor = anchor as? ARPlaneAnchor,node.childNodes.count < 1,updateCount < 1 {
            print("捕捉到平地")
            //2.创建一个平面    （系统捕捉到的平地是一个不规则大小的长方形，这里笔者将其变成一个长方形）
            let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            //3.使用Material渲染3D模型（默认模型是白色的，这里笔者改成红色）
            plane.firstMaterial?.diffuse.contents = UIColor.red
            //4.创建一个基于3D物体模型的节点
            planeNode = SCNNode(geometry: plane)
            //5.设置节点的位置为捕捉到的平地的锚点的中心位置  SceneKit框架中节点的位置position是一个基于3D坐标系的矢量坐标SCNVector3Make
            planeNode?.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
            //6.`SCNPlane`默认是竖着的,所以旋转一下以匹配水平的`ARPlaneAnchor`
            planeNode?.eulerAngles.x = -.pi / 2
            
            //7.更改透明度
            planeNode?.opacity = 0.25
            //8.添加到父节点中
            node.addChildNode(planeNode!)
            
            //9.上面的planeNode节点,大小/位置会随着检测到的平面而不断变化,方便起见,再添加一个相对固定的基准平面,用来放置游戏场景
            let base = SCNBox(width: 0.5, height: 0, length: 0.5, chamferRadius: 0);
            base.firstMaterial?.diffuse.contents = UIColor.gray;
            baseNode = SCNNode(geometry:base);
            baseNode?.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.z);
            
            node.addChildNode(baseNode!)
        }
    }
    
    // 更新锚点和对应的node之前调用,ARKit会自动更新anchor和node,使其相匹配
    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {
        // 只更新在`renderer(_:didAdd:for:)`中得到的配对的锚点和节点.
        guard let planeAnchor = anchor as?  ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane
            else { return }
        
        updateCount += 1
        if updateCount > 20 {//平面超过更新20次,捕捉到的特征点已经足够多了,可以显示进入游戏按钮
            DispatchQueue.main.async {
                self.playButton.isHidden = false
            }
        }
        
        // 平面的中心点可以会变动.
        planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        /*
         平面尺寸可能会变大,或者把几个小平面合并为一个大平面.合并时,`ARSCNView`自动删除同一个平面上的相应节点,然后调用该方法来更新保留的另一个平面的尺寸.(经过测试,合并时,保留第一个检测到的平面和对应节点)
         */
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
    }
    
    // 更新锚点和对应的node之后调用
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
    }
    // 移除锚点和对应node后
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        
    }
    
    // MARK: - ARSessionObserver
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        
        sessionInfoLabel.text = "Session失败: \(error.localizedDescription)"
        resetTracking()
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        
        sessionInfoLabel.text = "Session被打断"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        
        sessionInfoLabel.text = "Session打断结束"
        resetTracking()
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
}
