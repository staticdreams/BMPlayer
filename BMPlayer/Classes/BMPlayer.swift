//
//  BMPlayer.swift
//  Pods
//
//  Created by BrikerMan on 16/4/28.
//
//

import UIKit
import SnapKit
import MediaPlayer

enum BMPlayerState {
    case notSetURL      // 未设置URL
    case readyToPlay    // 可以播放
    case buffering      // 缓冲中
    case bufferFinished // 缓冲完毕
    case playedToTheEnd // 播放结束
    case error          // 出现错误
}

/// 枚举值，包含水平移动方向和垂直移动方向
enum BMPanDirection: Int {
    case horizontal = 0
    case vertical   = 1
}

enum BMPlayerItemType {
    case url
    case bmPlayerItem
}

public class BMPlayer: UIView {

    public var backBlock:(() -> Void)?
    
    var videoItem: BMPlayerItem!
    
    var currentDefinition = 0
    
    var playerLayer: BMPlayerLayerView?
    
    var controlView: BMPlayerCustomControlView!
    
    private var customControllView: BMPlayerCustomControlView?
    
    var playerItemType = BMPlayerItemType.url
    
    var videoItemURL: URL!
    
    var videoTitle = ""
    
    var isFullScreen:Bool {
        get {
            return UIApplication.shared.statusBarOrientation.isLandscape
        }
    }
    
    /// 滑动方向
    private var panDirection = BMPanDirection.horizontal
    /// 音量滑竿
    private var volumeViewSlider: UISlider!
    
    private let BMPlayerAnimationTimeInterval:Double                = 4.0
    private let BMPlayerControlBarAutoFadeOutTimeInterval:Double    = 0.5
    
    /// 用来保存时间状态
    private var sumTime         : TimeInterval = 0
    private var totalDuration   : TimeInterval = 0
    private var currentPosition : TimeInterval = 0
    private var shouldSeekTo    : TimeInterval = 0
    
    private var isURLSet        = false
    private var isSliderSliding = false
    private var isPauseByUser   = false
    private var isVolume        = false
    private var isMaskShowing   = false
    private var isSlowed        = false
    private var isMirrored      = false
    
    
    // MARK: - Public functions
    /**
     直接使用URL播放
     
     - parameter url:   视频URL
     - parameter title: 视频标题
     */
    public func playWithURL(_ url: URL, title: String = "") {
        playerItemType              = BMPlayerItemType.url
        videoItemURL                = url
        controlView.playerTitleLabel?.text = title
        
        if BMPlayerConf.shouldAutoPlay {
            playerLayer?.videoURL   = videoItemURL
            isURLSet                = true
        } else {
            controlView.hideLoader()
        }
    }
    
    /**
     播放可切换清晰度的视频
     
     - parameter items: 清晰度列表
     - parameter title: 视频标题
     - parameter definitionIndex: 起始清晰度
     */
    public func playWithPlayerItem(_ item:BMPlayerItem, definitionIndex: Int = 0) {
        playerItemType              = BMPlayerItemType.bmPlayerItem
        videoItem                   = item
        controlView.playerTitleLabel?.text = item.title
        currentDefinition           = definitionIndex
        controlView.prepareChooseDefinitionView(item.resource, index: definitionIndex)
        
        if BMPlayerConf.shouldAutoPlay {
            playerLayer?.videoURL   = videoItem.resource[currentDefinition].playURL
            isURLSet                = true
        } else {
            controlView.showCoverWithLink(item.cover)
        }
    }
    
    /**
     使用自动播放，参照pause函数
     */
    public func autoPlay() {
        if !isPauseByUser && isURLSet {
            self.play()
        }
    }
    
    /**
     手动播放
     */
    public func play() {
        if !isURLSet {
            if playerItemType == BMPlayerItemType.bmPlayerItem {
                playerLayer?.videoURL       = videoItem.resource[currentDefinition].playURL
            } else {
                playerLayer?.videoURL       = videoItemURL
            }
            controlView.hideCoverImageView()
            isURLSet                = true
        }
        playerLayer?.play()
        isPauseByUser = false
    }
    
    /**
     暂停
     
     - parameter allowAutoPlay: 是否允许自动播放，默认不允许，若允许则在调用autoPlay的情况下开始播放。否则autoPlay不会进行播放。
     */
    public func pause(allowAutoPlay allow: Bool = false) {
        playerLayer?.pause()
        isPauseByUser = !allow
    }
    
    /**
     开始自动隐藏UI倒计时
     */
    public func autoFadeOutControlBar() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideControlViewAnimated), object: nil)
        self.perform(#selector(hideControlViewAnimated), with: nil, afterDelay: BMPlayerAnimationTimeInterval)
    }
    
    /**
     取消UI自动隐藏
     */
    public func cancelAutoFadeOutControlBar() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }
    
    /**
     旋转屏幕时更新UI
     */
    public func updateUI(_ isFullScreen: Bool) {
        controlView.updateUI(isFullScreen)
    }
    
    /**
     准备销毁，适用于手动隐藏等场景
     */
    public func prepareToDealloc() {
        playerLayer?.prepareToDeinit()
    }
    
    
    // MARK: - Action Response
    private func playStateDidChanged() {
        if isSliderSliding { return }
        if let player = playerLayer {
            if player.isPlaying {
                autoFadeOutControlBar()
                controlView.playerPlayButton?.isSelected = true
            } else {
                controlView.playerPlayButton?.isSelected = false
            }
        }
    }
    
    
    @objc private func hideControlViewAnimated() {
        UIView.animate(withDuration: BMPlayerControlBarAutoFadeOutTimeInterval, animations: {
            self.controlView.hidePlayerUIComponents()
            if self.isFullScreen {
                UIApplication.shared.setStatusBarHidden(true, with: UIStatusBarAnimation.fade)
            }
        }) { (_) in
            self.isMaskShowing = false
        }
    }
    
    @objc private func showControlViewAnimated() {
        UIView.animate(withDuration: BMPlayerControlBarAutoFadeOutTimeInterval, animations: {
            self.controlView.showPlayerUIComponents()
            UIApplication.shared.setStatusBarHidden(false, with: UIStatusBarAnimation.fade)
        }) { (_) in
            self.autoFadeOutControlBar()
            self.isMaskShowing = true
        }
    }
    
    @objc private func tapGestureTapped(_ sender: UIGestureRecognizer) {
        if isMaskShowing {
            hideControlViewAnimated()
            autoFadeOutControlBar()
        } else {
            showControlViewAnimated()
        }
    }
    
    @objc private func panDirection(_ pan: UIPanGestureRecognizer) {
        // 根据在view上Pan的位置，确定是调音量还是亮度
        let locationPoint = pan.location(in: self)
        
        // 我们要响应水平移动和垂直移动
        // 根据上次和本次移动的位置，算出一个速率的point
        let velocityPoint = pan.velocity(in: self)
        
        // 判断是垂直移动还是水平移动
        switch pan.state {
        case UIGestureRecognizerState.began:
            // 使用绝对值来判断移动的方向
            
            let x = fabs(velocityPoint.x)
            let y = fabs(velocityPoint.y)
            
            if x > y {
                self.panDirection = BMPanDirection.horizontal
                
                // 给sumTime初值
                if let player = playerLayer?.player {
                    let time = player.currentTime()
                    self.sumTime = TimeInterval(time.value) / TimeInterval(time.timescale)
                }
                
            } else {
                self.panDirection = BMPanDirection.vertical
                if locationPoint.x > self.bounds.size.width / 2 {
                    self.isVolume = true
                } else {
                    self.isVolume = false
                }
            }
            
        case UIGestureRecognizerState.changed:
            cancelAutoFadeOutControlBar()
            switch self.panDirection {
            case BMPanDirection.horizontal:
                self.horizontalMoved(velocityPoint.x)
            case BMPanDirection.vertical:
                self.verticalMoved(velocityPoint.y)
            }
        case UIGestureRecognizerState.ended:
            // 移动结束也需要判断垂直或者平移
            // 比如水平移动结束时，要快进到指定位置，如果这里没有判断，当我们调节音量完之后，会出现屏幕跳动的bug
            switch (self.panDirection) {
            case BMPanDirection.horizontal:
                controlView.hideSeekToView()
                isSliderSliding = false
                playerLayer?.seekToTime(Int(self.sumTime), completionHandler: nil)
                // 把sumTime滞空，不然会越加越多
                self.sumTime = 0.0
                
            //                controlView.showLoader()
            case BMPanDirection.vertical:
                self.isVolume = false
            }
        default:
            break
        }
    }
    
    private func verticalMoved(_ value: CGFloat) {
        self.isVolume ? (self.volumeViewSlider.value -= Float(value / 10000)) : (UIScreen.main.brightness -= value / 10000)
    }
    
    private func horizontalMoved(_ value: CGFloat) {
        isSliderSliding = true
        if let playerItem = playerLayer?.playerItem {
            // 每次滑动需要叠加时间，通过一定的比例，使滑动一直处于统一水平
            self.sumTime = self.sumTime + TimeInterval(value) / 100.0 * (TimeInterval(self.totalDuration)/400)
            
            let totalTime       = playerItem.duration
            
            // 防止出现NAN
            if totalTime.timescale == 0 { return }
            
            let totalDuration   = TimeInterval(totalTime.value) / TimeInterval(totalTime.timescale)
            if (self.sumTime > totalDuration) { self.sumTime = totalDuration}
            if (self.sumTime < 0){ self.sumTime = 0}
            
            let targetTime      = formatSecondsToString(sumTime)
            
            controlView.playerTimeSlider?.value      = Float(sumTime / totalDuration)
            controlView.playerCurrentTimeLabel?.text       = targetTime
            controlView.showSeekToView(sumTime, isAdd: value > 0)
            
        }
    }
    
    @objc private func progressSliderTouchBegan(_ sender: UISlider)  {
        playerLayer?.onTimeSliderBegan()
        isSliderSliding = true
    }
    
    @objc private func progressSliderValueChanged(_ sender: UISlider)  {
        self.pause(allowAutoPlay: true)
        cancelAutoFadeOutControlBar()
    }
    
    @objc private func progressSliderTouchEnded(_ sender: UISlider)  {
        isSliderSliding = false
        autoFadeOutControlBar()
        let target = self.totalDuration * Double(sender.value)
        playerLayer?.seekToTime(Int(target), completionHandler: nil)
        autoPlay()
    }
    
    @objc private func backButtonPressed(_ button: UIButton) {
        if isFullScreen {
            fullScreenButtonPressed(nil)
        } else {
            playerLayer?.prepareToDeinit()
            backBlock?()
        }
    }
    
    @objc private func slowButtonPressed(_ button: UIButton) {
        autoFadeOutControlBar()
        if isSlowed {
            self.playerLayer?.player?.rate = 1.0
            self.isSlowed = false
            self.controlView.playerSlowButton?.setTitle("慢放", for: UIControlState())
        } else {
            self.playerLayer?.player?.rate = 0.5
            self.isSlowed = true
            self.controlView.playerSlowButton?.setTitle("正常", for: UIControlState())
        }
    }
    
    @objc private func mirrorButtonPressed(_ button: UIButton) {
        autoFadeOutControlBar()
        if isMirrored {
            self.playerLayer?.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            self.isMirrored = false
            self.controlView.playerMirrorButton?.setTitle("镜像", for: UIControlState())
        } else {
            self.playerLayer?.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            self.isMirrored = true
            self.controlView.playerMirrorButton?.setTitle("正常", for: UIControlState())
        }    }
    
    @objc private func replayButtonPressed() {
        playerLayer?.seekToTime(0, completionHandler: {
            
        })
        self.play()
    }
    
    @objc private func playButtonPressed(_ button: UIButton) {
        if button.isSelected {
            self.pause()
        } else {
            self.play()
        }
    }
    
    @objc private func onOrientationChanged() {
        self.updateUI(isFullScreen)
    }
    
    @objc private func fullScreenButtonPressed(_ button: UIButton?) {
        if !isURLSet {
            //            self.play()
        }
        controlView.updateUI(!self.isFullScreen)
        if isFullScreen {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIApplication.shared.setStatusBarHidden(false, with: UIStatusBarAnimation.fade)
            UIApplication.shared.setStatusBarOrientation(UIInterfaceOrientation.portrait, animated: false)
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIApplication.shared.setStatusBarHidden(false, with: UIStatusBarAnimation.fade)
            UIApplication.shared.setStatusBarOrientation(UIInterfaceOrientation.landscapeRight, animated: false)
        }
    }
    
    // MARK: - 生命周期
    deinit {
        playerLayer?.pause()
        playerLayer?.prepareToDeinit()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationDidChangeStatusBarOrientation, object: nil)
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
    
    public convenience init (customControllView: BMPlayerCustomControlView?) {
        self.init(frame:CGRect.zero)
        self.customControllView = customControllView
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
    
    public convenience init() {
        self.init(customControllView:nil)
    }

    
    private func formatSecondsToString(_ secounds: TimeInterval) -> String {
        let Min = Int(secounds / 60)
        let Sec = Int(secounds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", Min, Sec)
    }
    
    // MARK: - 初始化
    private func initUI() {
        self.backgroundColor = UIColor.black
        
        if let customView = customControllView {
            controlView = customView
        } else {
            controlView =  BMPlayerControlView()
        }
        
        addSubview(controlView.getView)
        controlView.updateUI(isFullScreen)
        controlView.delegate = self
        controlView.getView.snp_makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapGestureTapped(_:)))
        self.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panDirection(_:)))
        //        panGesture.delegate = self
        self.addGestureRecognizer(panGesture)
    }
    
    private func initUIData() {
        controlView.playerPlayButton?.addTarget(self, action: #selector(self.playButtonPressed(_:)), for: UIControlEvents.touchUpInside)
        controlView.playerFullScreenButton?.addTarget(self, action: #selector(self.fullScreenButtonPressed(_:)), for: UIControlEvents.touchUpInside)
        controlView.playerBackButton?.addTarget(self, action: #selector(self.backButtonPressed(_:)), for: UIControlEvents.touchUpInside)
        controlView.playerTimeSlider?.addTarget(self, action: #selector(progressSliderTouchBegan(_:)), for: UIControlEvents.touchDown)
        controlView.playerTimeSlider?.addTarget(self, action: #selector(progressSliderValueChanged(_:)), for: UIControlEvents.valueChanged)
        controlView.playerTimeSlider?.addTarget(self, action: #selector(progressSliderTouchEnded(_:)), for: [UIControlEvents.touchUpInside,UIControlEvents.touchCancel, UIControlEvents.touchUpOutside])
        controlView.playerSlowButton?.addTarget(self, action: #selector(slowButtonPressed(_:)), for: .touchUpInside)
        controlView.playerMirrorButton?.addTarget(self, action: #selector(mirrorButtonPressed(_:)), for: .touchUpInside)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.onOrientationChanged), name: NSNotification.Name.UIApplicationDidChangeStatusBarOrientation, object: nil)
    }
    
    private func configureVolume() {
        let volumeView = MPVolumeView()
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                self.volumeViewSlider = slider
            }
        }
    }
    
    private func preparePlayer() {
        playerLayer = BMPlayerLayerView()
        insertSubview(playerLayer!, at: 0)
        playerLayer!.snp_makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        playerLayer!.delegate = self
        controlView.showLoader()
        self.layoutIfNeeded()
    }
}

extension BMPlayer: BMPlayerLayerViewDelegate {
    func bmPlayer(player: BMPlayerLayerView, playerIsPlaying playing: Bool) {
        playStateDidChanged()
    }
    
    func bmPlayer(player: BMPlayerLayerView ,loadedTimeDidChange  loadedDuration: TimeInterval , totalDuration: TimeInterval) {
        self.totalDuration = totalDuration
        BMPlayerManager.shared.log("loadedTimeDidChange - \(loadedDuration) - \(totalDuration)")
        controlView.playerProgressView?.setProgress(Float(loadedDuration)/Float(totalDuration), animated: true)
    }
    
    func bmPlayer(player: BMPlayerLayerView, playerStateDidChange state: BMPlayerState) {
        BMPlayerManager.shared.log("playerStateDidChange - \(state)")
        switch state {
        case BMPlayerState.readyToPlay:
            if shouldSeekTo != 0 {
                playerLayer?.seekToTime(Int(shouldSeekTo), completionHandler: {
                    
                })
                shouldSeekTo = 0
            }
        case BMPlayerState.buffering:
            cancelAutoFadeOutControlBar()
            controlView.showLoader()
            playStateDidChanged()
        case BMPlayerState.bufferFinished:
            controlView.hideLoader()
            playStateDidChanged()
            autoPlay()
        case BMPlayerState.playedToTheEnd:
            self.pause()
            controlView.showPlayToTheEndView()
        default:
            break
        }
    }
    
    func bmPlayer(player: BMPlayerLayerView, playTimeDidChange currentTime: TimeInterval, totalTime: TimeInterval) {
        self.currentPosition = currentTime
        BMPlayerManager.shared.log("playTimeDidChange - \(currentTime) - \(totalTime)")
        totalDuration = totalTime
        if isSliderSliding {
            return
        }
        controlView.playerCurrentTimeLabel?.text = formatSecondsToString(currentTime)
        controlView.playerTotalTimeLabel?.text = formatSecondsToString(totalTime)
        
        controlView.playerTimeSlider?.value    = Float(currentTime) / Float(totalTime)
    }
}

extension BMPlayer: BMPlayerControlViewDelegate {
    public func controlViewDidChooseDefition(_ index: Int) {
        shouldSeekTo                = currentPosition
        playerLayer?.resetPlayer()
        playerLayer?.videoURL       = videoItem.resource[index].playURL
        currentDefinition           = index
    }
    
    public func controlViewDidPressOnReply() {
        replayButtonPressed()
    }
}
