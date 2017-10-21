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


let boxheight:CGFloat = 0.05
let boxLengthWidth:CGFloat = 0.4
let actionOffet:Float = 0.6
let actionSpeed:Float = 0.011

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet weak var sessionInfoLabel: UILabel!
    
    @IBOutlet weak var playButton: UIButton!
    
    @IBOutlet weak var restartButton: UIButton!
    
    @IBOutlet weak var scoreLabel: UILabel!
    
    // 识别出平面后,放上游戏的基础节点,相对固定于真实世界场景中
    weak var baseNode: SCNNode?
    // 识别出平面锚点后,用来标识识别的平面,会不断刷新大小和位置
    weak var planeNode: SCNNode?
    // 刷新次数,超过一定次数才说明这个平面足够明显,足够稳定.可以开始游戏
    var updateCount: NSInteger = 0
    
    var gameNode:SCNNode?
    
    var direction = true
    var height = 0
    
    
    var previousSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
    var previousPosition = SCNVector3(0, boxheight*0.5, 0)
    var currentSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
    var currentPosition = SCNVector3Zero
    
    var offset = SCNVector3Zero
    var absoluteOffset = SCNVector3Zero
    var newSize = SCNVector3Zero
    
    
    var perfectMatches = 0
    var sounds = [String: SCNAudioSource]()

    override func viewDidLoad() {
        super.viewDidLoad()
        playButton.isHidden = true
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        //显示debug特征点
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        // Create a new scene
        let scene = SCNScene()
        // Set the scene to the view
        sceneView.scene = scene
        
        loadSound(name: "GameOver", path: "art.scnassets/Audio/GameOver.wav")
        loadSound(name: "PerfectFit", path: "art.scnassets/Audio/PerfectFit.wav")
        loadSound(name: "SliceBlock", path: "art.scnassets/Audio/SliceBlock.wav")
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: nil) { (noti) in
            self.resetAll()
        }
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
        print("viewWillAppear")
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
        baseNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        //4.载入游戏场景
        
        gameNode?.removeFromParentNode()//移除前一次游戏的场景节点
        gameNode = SCNScene(named: "art.scnassets/Scenes/GameScene.scn")!.rootNode
        baseNode?.addChildNode(gameNode!)
        
        height = 0
        scoreLabel.text = "\(height)"
        
        direction = true
        perfectMatches = 0
        
        
        let boxNode = SCNNode(geometry: SCNBox(width: boxLengthWidth, height: boxheight, length: boxLengthWidth, chamferRadius: 0))
        boxNode.position.z = -actionOffet
        boxNode.position.y = Float(boxheight * 0.5)
        boxNode.name = "Block\(height)"
        boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1 * CGFloat(height % 10), green: 0.03*CGFloat(height%30), blue: 1-0.1 * CGFloat(height % 10), alpha: 1)
        gameNode?.addChildNode(boxNode)
    }
    @IBAction func restartButtonClick(_ sender: UIButton) {
        resetAll()
    }
    @IBAction func handleTap(_ sender: Any) {
        if let currentBoxNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
            currentPosition = currentBoxNode.presentation.position
            let boundsMin = currentBoxNode.boundingBox.min
            let boundsMax = currentBoxNode.boundingBox.max
            currentSize = boundsMax - boundsMin
            
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            newSize = currentSize - absoluteOffset
            
            if height % 2 == 0 && newSize.z <= 0 {
                gameOver()
                playSound(sound: "GameOver", node: currentBoxNode)
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            } else if height % 2 != 0 && newSize.x <= 0 {
                gameOver()
                playSound(sound: "GameOver", node: currentBoxNode)
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            }
            
            checkPerfectMatch(currentBoxNode)
            
            currentBoxNode.geometry = SCNBox(width: CGFloat(newSize.x), height: boxheight, length: CGFloat(newSize.z), chamferRadius: 0)
            currentBoxNode.position = SCNVector3Make(currentPosition.x + (offset.x/2), currentPosition.y, currentPosition.z + (offset.z/2))
            currentBoxNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
            currentBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1 * CGFloat(height % 10), green: 0.03*CGFloat(height%30), blue: 1-0.1 * CGFloat(height % 10), alpha: 1)
            addBrokenBlock(currentBoxNode)
            addNewBlock(currentBoxNode)
            playSound(sound: "SliceBlock", node: currentBoxNode)
            
            if height >= 5 {
                let moveUpAction = SCNAction.move(by: SCNVector3Make(0.0, Float(-boxheight), 0.0), duration: 0.2)
                
                gameNode?.runAction(moveUpAction)
            }
            
            scoreLabel.text = "\(height+1)"
            
            previousSize = SCNVector3Make(newSize.x, Float(boxheight), newSize.z)
            previousPosition = currentBoxNode.position
            height += 1
        }
    }
    
}
// MARK:- 私有方法
extension ViewController {
    func addNewBlock(_ currentBoxNode: SCNNode) {
        let newBoxNode = SCNNode(geometry: SCNBox(width: CGFloat(newSize.x), height: boxheight, length: CGFloat(newSize.z), chamferRadius: 0))
        newBoxNode.position = SCNVector3Make(currentBoxNode.position.x, currentPosition.y + Float(boxheight), currentBoxNode.position.z)
        newBoxNode.name = "Block\(height+1)"
        newBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1 * CGFloat((height+1) % 10), green: 0.03*CGFloat((height+1)%30), blue: 1-0.1 * CGFloat((height+1) % 10), alpha: 1)
        
        if height % 2 == 0 {
            newBoxNode.position.x = -actionOffet
        } else {
            newBoxNode.position.z = -actionOffet
        }
        
        gameNode?.addChildNode(newBoxNode)
    }
    
    func addBrokenBlock(_ currentBoxNode: SCNNode) {
        let brokenBoxNode = SCNNode()
        brokenBoxNode.name = "Broken \(height)"
        
        if height % 2 == 0 && absoluteOffset.z > 0 {
            // 1
            brokenBoxNode.geometry = SCNBox(width: CGFloat(currentSize.x), height: boxheight, length: CGFloat(absoluteOffset.z), chamferRadius: 0)
            
            // 2
            if offset.z > 0 {
                brokenBoxNode.position.z = currentBoxNode.position.z - (offset.z/2) - ((currentSize - offset).z/2)
            } else {
                brokenBoxNode.position.z = currentBoxNode.position.z - (offset.z/2) + ((currentSize + offset).z/2)
            }
            brokenBoxNode.position.x = currentBoxNode.position.x
            brokenBoxNode.position.y = currentPosition.y
            
            // 3
            brokenBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: brokenBoxNode.geometry!, options: nil))
            brokenBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1 * CGFloat(height % 10), green: 0.03*CGFloat(height%30), blue: 1-0.1 * CGFloat(height % 10), alpha: 1)
            gameNode?.addChildNode(brokenBoxNode)
            
            // 4
        } else if height % 2 != 0 && absoluteOffset.x > 0 {
            brokenBoxNode.geometry = SCNBox(width: CGFloat(absoluteOffset.x), height: boxheight, length: CGFloat(currentSize.z), chamferRadius: 0)
            
            if offset.x > 0 {
                brokenBoxNode.position.x = currentBoxNode.position.x - (offset.x/2) - ((currentSize - offset).x/2)
            } else {
                brokenBoxNode.position.x = currentBoxNode.position.x - (offset.x/2) + ((currentSize + offset).x/2)
            }
            brokenBoxNode.position.y = currentPosition.y
            brokenBoxNode.position.z = currentBoxNode.position.z
            
            brokenBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: brokenBoxNode.geometry!, options: nil))
            brokenBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1 * CGFloat(height % 10), green: 0.03*CGFloat(height%30), blue: 1-0.1 * CGFloat(height % 10), alpha: 1)
            gameNode?.addChildNode(brokenBoxNode)
        }
    }
    
    func checkPerfectMatch(_ currentBoxNode: SCNNode) {
        if height % 2 == 0 && absoluteOffset.z <= 0.005 {
            playSound(sound: "PerfectFit", node: currentBoxNode)
            currentBoxNode.position.z = previousPosition.z
            currentPosition.z = previousPosition.z
            perfectMatches += 1
            if perfectMatches >= 7 && currentSize.z < 1 {
                newSize.z += 0.005
            }
            
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            newSize = currentSize - absoluteOffset
        } else if height % 2 != 0 && absoluteOffset.x <= 0.005 {
            playSound(sound: "PerfectFit", node: currentBoxNode)
            currentBoxNode.position.x = previousPosition.x
            currentPosition.x = previousPosition.x
            perfectMatches += 1
            if perfectMatches >= 7 && currentSize.x < 1 {
                newSize.x += 0.005
            }
            
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            newSize = currentSize - absoluteOffset
        } else {
            perfectMatches = 0
        }
    }

    func loadSound(name: String, path: String) {
        if let sound = SCNAudioSource(fileNamed: path) {
            sound.isPositional = false
            sound.volume = 1
            sound.load()
            sounds[name] = sound
        }
    }
    
    func playSound(sound: String, node: SCNNode) {
        node.runAction(SCNAction.playAudio(sounds[sound]!, waitForCompletion: false))
    }
    
    
    func gameOver() {
        
        let fullAction = SCNAction.customAction(duration: 0.3) { _,_ in
            let moveAction = SCNAction.move(to: SCNVector3Make(0, 0, 0), duration: 0.3)
            self.gameNode?.runAction(moveAction)
        }
        
        gameNode?.runAction(fullAction)
        playButton.isHidden = false
    }
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
        //3.重置游戏数据
        height = 0
        scoreLabel.text = "\(height)"
        
        direction = true
        perfectMatches = 0
        print("resetAll")
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
    
        //1.获取捕捉到的平地锚点,只识别并添加一个平面(似乎是多线程的问题,有时updateCount重置后又更新了一次变成了1,故updateCount改为 <= 1比较合理)
        if let planeAnchor = anchor as? ARPlaneAnchor,node.childNodes.count < 1,updateCount <= 1 {
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
    
    // MARK:- SCNSceneRendererDelegate
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let gameNode2 = gameNode else {
            return
        }
        for node in gameNode2.childNodes {
            if node.presentation.position.y <= -10 {
                node.removeFromParentNode()
            }
        }
        
        // 1
        if let currentNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
            // 2
            if height % 2 == 0 {
                // 3
                if currentNode.position.z >= actionOffet {
                    direction = false
                } else if currentNode.position.z <= -actionOffet {
                    direction = true
                }
                
                // 4
                switch direction {
                case true:
                    currentNode.position.z += actionSpeed
                case false:
                    currentNode.position.z -= actionSpeed
                }
                // 5
            } else {
                if currentNode.position.x >= actionOffet {
                    direction = false
                } else if currentNode.position.x <= -actionOffet {
                    direction = true
                }
                
                switch direction {
                case true:
                    currentNode.position.x += actionSpeed
                case false:
                    currentNode.position.x -= actionSpeed
                }
            }
        }
    }
}
