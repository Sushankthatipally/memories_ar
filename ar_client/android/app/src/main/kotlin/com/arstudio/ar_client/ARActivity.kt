package com.arstudio.ar_client

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.HapticFeedbackConstants
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AlphaAnimation
import android.view.animation.Animation
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ProgressBar
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.cardview.widget.CardView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.ar.core.AugmentedImage
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Config
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.arcore.getUpdatedAugmentedImages
import java.io.File

class ARActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "ARActivity"
        
        // Animation durations
        private const val UNFOLD_DURATION_MS = 500L      // Cinematic unfold animation
        private const val AUDIO_FADE_IN_MS = 1000L       // Audio fade in duration
        private const val AUDIO_FADE_OUT_MS = 500L       // Audio fade out duration
        private const val VIDEO_FADE_OUT_MS = 300L       // Video fade out duration
    }

    private lateinit var sceneView: ARSceneView
    private lateinit var backButton: ImageButton
    private lateinit var muteButton: ImageButton
    private lateinit var freezeButton: ImageButton
    private lateinit var rootLayout: FrameLayout
    private lateinit var scanGuide: FrameLayout
    private lateinit var loadingSpinner: ProgressBar
    
    private val handler = Handler(Looper.getMainLooper())
    
    // Freeze Frame state
    private var isFrozen = false
    private var frozenImageIndex: Int? = null

    // Data from Flutter
    private var imagePaths: ArrayList<String>? = null
    private var videoPaths: ArrayList<String>? = null

    // Track active videos per detected image
    private val activeVideoPlayers = HashMap<Int, MediaPlayer>()
    private val activeVideoViews = HashMap<Int, TextureView>()
    private val activeCardViews = HashMap<Int, CardView>()  // Rounded corner containers
    private val trackedImages = HashMap<Int, AugmentedImage>()
    
    // Track volume animators for smooth audio transitions
    private val volumeAnimators = HashMap<Int, ValueAnimator>()
    
    // Track current volume levels per player
    private val currentVolumes = HashMap<Int, Float>()
    
    // Track visibility state for proper pause/resume
    private val isVideoVisible = HashMap<Int, Boolean>()
    
    // Mute state
    private var isMuted = false
    private var isVideoPlaying = false
    
    // Polaroid frame settings
    private val CORNER_RADIUS_DP = 16f  // Rounded corners like modern photos
    private val BORDER_WIDTH_DP = 6f    // White Polaroid-style border
    
    // Track when videos were last visible (for reset logic)
    private val lastVisibleTime = HashMap<Int, Long>()
    private val VIDEO_RESET_THRESHOLD_MS = 2000L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Full screen immersive mode
        hideSystemUI()
        
        setContentView(R.layout.activity_ar)

        rootLayout = findViewById<FrameLayout>(android.R.id.content).getChildAt(0) as FrameLayout
        sceneView = findViewById(R.id.sceneView)
        backButton = findViewById(R.id.backButton)
        muteButton = findViewById(R.id.muteButton)
        freezeButton = findViewById(R.id.freezeButton)
        scanGuide = findViewById(R.id.scanGuide)
        loadingSpinner = findViewById(R.id.loadingSpinner)

        backButton.setOnClickListener { finish() }
        muteButton.setOnClickListener { toggleMute() }
        freezeButton.setOnClickListener { toggleFreeze() }
        
        // Animate scan guide
        startScanGuideAnimation()

        // Get data from Flutter
        imagePaths = intent.getStringArrayListExtra("IMAGE_PATHS")
        videoPaths = intent.getStringArrayListExtra("VIDEO_PATHS")

        if (imagePaths.isNullOrEmpty() || videoPaths.isNullOrEmpty()) {
            Toast.makeText(this, "No images or videos provided", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        Log.d(TAG, "Received ${imagePaths?.size} images and ${videoPaths?.size} videos")
        setupARCore()
    }

    private fun hideSystemUI() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).let { controller ->
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun toggleMute() {
        isMuted = !isMuted
        performHapticFeedback()
        
        // Update all active players with fade
        activeVideoPlayers.forEach { (imageIndex, player) ->
            if (isMuted) {
                fadeOutAudio(imageIndex, 200L) // Quick fade when muting
            } else {
                fadeInAudio(imageIndex, 200L) // Quick fade when unmuting
            }
        }
        
        // Update button appearance
        muteButton.alpha = if (isMuted) 0.5f else 1.0f
        muteButton.setImageResource(
            if (isMuted) android.R.drawable.ic_lock_silent_mode 
            else android.R.drawable.ic_lock_silent_mode_off
        )
    }

    // ========== FREEZE FRAME FEATURE ==========
    
    private fun toggleFreeze() {
        if (isFrozen) {
            unfreezeVideo()
        } else {
            freezeCurrentVideo()
        }
    }
    
    private fun freezeCurrentVideo() {
        // Find the currently active/visible video
        val activeIndex = isVideoVisible.entries.find { it.value }?.key ?: return
        val cardView = activeCardViews[activeIndex] ?: return
        val mediaPlayer = activeVideoPlayers[activeIndex] ?: return
        
        isFrozen = true
        frozenImageIndex = activeIndex
        performHapticFeedback()
        
        Log.d(TAG, "🔒 Freezing video at index $activeIndex")
        
        runOnUiThread {
            // Calculate centered position with comfortable viewing size
            val screenWidth = rootLayout.width
            val screenHeight = rootLayout.height
            
            // Make video larger for comfortable viewing (80% of screen width, maintain aspect ratio)
            val videoWidth = mediaPlayer.videoWidth
            val videoHeight = mediaPlayer.videoHeight
            val aspectRatio = if (videoHeight > 0) videoWidth.toFloat() / videoHeight else 16f/9f
            
            val targetWidth = (screenWidth * 0.85f).toInt()
            val targetHeight = (targetWidth / aspectRatio).toInt().coerceAtMost((screenHeight * 0.7f).toInt())
            val adjustedWidth = if (targetHeight == (screenHeight * 0.7f).toInt()) {
                (targetHeight * aspectRatio).toInt()
            } else {
                targetWidth
            }
            
            val centerX = (screenWidth - adjustedWidth) / 2
            val centerY = (screenHeight - targetHeight) / 2
            
            // Animate to center with scale up
            cardView.animate()
                .x(centerX.toFloat())
                .y(centerY.toFloat())
                .setDuration(400L)
                .setInterpolator(DecelerateInterpolator())
                .start()
            
            // Animate size change
            val params = cardView.layoutParams as FrameLayout.LayoutParams
            val startWidth = params.width
            val startHeight = params.height
            
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 400L
                interpolator = DecelerateInterpolator()
                addUpdateListener { animation ->
                    val progress = animation.animatedValue as Float
                    params.width = (startWidth + (adjustedWidth - startWidth) * progress).toInt()
                    params.height = (startHeight + (targetHeight - startHeight) * progress).toInt()
                    cardView.layoutParams = params
                }
                start()
            }
            
            // Update freeze button appearance
            freezeButton.alpha = 0.5f
            freezeButton.setImageResource(android.R.drawable.ic_menu_revert)
            
            // Hide scan guide when frozen
            scanGuide.visibility = View.GONE
            scanGuide.clearAnimation()
        }
    }
    
    private fun unfreezeVideo() {
        isFrozen = false
        frozenImageIndex = null
        performHapticFeedback()
        
        Log.d(TAG, "🔓 Unfreezing video - resuming AR tracking")
        
        runOnUiThread {
            // Reset freeze button appearance
            freezeButton.alpha = 1.0f
            freezeButton.setImageResource(android.R.drawable.ic_menu_view)
            
            // Show scan guide again
            scanGuide.visibility = View.VISIBLE
            startScanGuideAnimation()
        }
    }
    
    private fun showFreezeButton() {
        runOnUiThread {
            freezeButton.visibility = View.VISIBLE
            freezeButton.alpha = 0f
            freezeButton.animate()
                .alpha(1f)
                .setDuration(200L)
                .start()
        }
    }
    
    private fun hideFreezeButton() {
        runOnUiThread {
            freezeButton.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction {
                    freezeButton.visibility = View.GONE
                }
                .start()
        }
    }

    // ========== AUDIO FADE ANIMATIONS ==========
    
    private fun fadeInAudio(imageIndex: Int, duration: Long = AUDIO_FADE_IN_MS) {
        if (isMuted) return
        
        val player = activeVideoPlayers[imageIndex] ?: return
        
        // Cancel any existing animation
        volumeAnimators[imageIndex]?.cancel()
        
        val startVolume = currentVolumes[imageIndex] ?: 0f
        val targetVolume = 1f
        
        val animator = ValueAnimator.ofFloat(startVolume, targetVolume).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                val volume = animation.animatedValue as Float
                currentVolumes[imageIndex] = volume
                try {
                    player.setVolume(volume, volume)
                } catch (e: Exception) {}
            }
        }
        
        volumeAnimators[imageIndex] = animator
        animator.start()
        Log.d(TAG, "🔊 Audio fading in for image $imageIndex")
    }
    
    private fun fadeOutAudio(imageIndex: Int, duration: Long = AUDIO_FADE_OUT_MS) {
        val player = activeVideoPlayers[imageIndex] ?: return
        
        // Cancel any existing animation
        volumeAnimators[imageIndex]?.cancel()
        
        val startVolume = currentVolumes[imageIndex] ?: 1f
        val targetVolume = 0f
        
        val animator = ValueAnimator.ofFloat(startVolume, targetVolume).apply {
            this.duration = duration
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val volume = animation.animatedValue as Float
                currentVolumes[imageIndex] = volume
                try {
                    player.setVolume(volume, volume)
                } catch (e: Exception) {}
            }
        }
        
        volumeAnimators[imageIndex] = animator
        animator.start()
        Log.d(TAG, "🔇 Audio fading out for image $imageIndex")
    }

    // ========== HAPTIC FEEDBACK ==========
    
    private fun performHapticFeedback() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(50)
                }
            }
        } catch (e: Exception) {
            rootLayout.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        }
    }

    private fun performStrongHapticFeedback() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                // Double tap pattern for "found" feedback
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 80, 80, 80), -1))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 80, 80, 80), -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(longArrayOf(0, 80, 80, 80), -1)
                }
            }
        } catch (e: Exception) {
            rootLayout.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        }
    }

    // ========== UI ANIMATIONS ==========

    private fun startScanGuideAnimation() {
        val pulseAnimation = AlphaAnimation(0.3f, 1.0f).apply {
            duration = 1000
            repeatCount = Animation.INFINITE
            repeatMode = Animation.REVERSE
        }
        scanGuide.startAnimation(pulseAnimation)
    }

    private fun showLoading() {
        runOnUiThread {
            loadingSpinner.visibility = View.VISIBLE
            scanGuide.clearAnimation()
            scanGuide.visibility = View.GONE
        }
    }

    private fun hideLoading() {
        runOnUiThread {
            loadingSpinner.visibility = View.GONE
        }
    }

    private fun showVideoPlaying() {
        isVideoPlaying = true
        runOnUiThread {
            if (!isFrozen) {
                scanGuide.clearAnimation()
                scanGuide.visibility = View.GONE
            }
            showFreezeButton()
        }
    }

    private fun showScanning() {
        isVideoPlaying = false
        runOnUiThread {
            if (!isFrozen) {
                scanGuide.visibility = View.VISIBLE
                startScanGuideAnimation()
                hideFreezeButton()
            }
        }
    }
    
    // ========== CINEMATIC UNFOLD ANIMATION ==========
    
    private fun playCinematicUnfold(cardView: CardView, imageIndex: Int) {
        runOnUiThread {
            hideLoading()
            
            // Start from center, scaled down and transparent
            cardView.alpha = 0f
            cardView.scaleX = 0.3f
            cardView.scaleY = 0.3f
            cardView.visibility = View.VISIBLE
            
            // Animate to full size with fade in - the "blooming" effect
            cardView.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(UNFOLD_DURATION_MS)
                .setInterpolator(DecelerateInterpolator(2f))
                .withStartAction {
                    // Start audio fade-in simultaneously
                    fadeInAudio(imageIndex)
                }
                .start()
            
            Log.d(TAG, "✨ Cinematic unfold started for image $imageIndex")
        }
    }
    
    private fun fadeOutVideo(imageIndex: Int, onComplete: (() -> Unit)? = null) {
        val cardView = activeCardViews[imageIndex] ?: return
        
        // Mark as not visible
        isVideoVisible[imageIndex] = false
        
        runOnUiThread {
            // Fade out audio first
            fadeOutAudio(imageIndex, VIDEO_FADE_OUT_MS)
            
            // Then fade out video
            cardView.animate()
                .alpha(0f)
                .scaleX(0.8f)
                .scaleY(0.8f)
                .setDuration(VIDEO_FADE_OUT_MS)
                .setInterpolator(AccelerateDecelerateInterpolator())
                .withEndAction {
                    cardView.visibility = View.GONE
                    // Reset scale for next time
                    cardView.scaleX = 1f
                    cardView.scaleY = 1f
                    onComplete?.invoke()
                }
                .start()
        }
    }

    // ========== AR CORE SETUP ==========

    private fun setupARCore() {
        sceneView.configureSession { session, config ->
            config.focusMode = Config.FocusMode.AUTO
            config.planeFindingMode = Config.PlaneFindingMode.DISABLED
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED

            val database = AugmentedImageDatabase(session)
            setupImageDatabase(database)
            config.augmentedImageDatabase = database
        }

        sceneView.onSessionUpdated = { _, frame ->
            frame.getUpdatedAugmentedImages().forEach { augmentedImage ->
                handleAugmentedImage(augmentedImage)
            }
            updateVideoPositions(frame)
        }
    }

    private fun setupImageDatabase(database: AugmentedImageDatabase) {
        var addedCount = 0
        imagePaths?.forEachIndexed { index, path ->
            try {
                val file = File(path)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(path)
                    if (bitmap != null) {
                        database.addImage("image_$index", bitmap, 0.20f)
                        Log.d(TAG, "✅ Added image_$index: ${bitmap.width}x${bitmap.height}")
                        addedCount++
                        bitmap.recycle()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error loading image $index: ${e.message}")
            }
        }
        Log.d(TAG, "📷 Database ready: $addedCount images")
    }

    private fun handleAugmentedImage(augmentedImage: AugmentedImage) {
        val imageIndex = augmentedImage.name.removePrefix("image_").toIntOrNull() ?: return
        
        // Use FULL_TRACKING for stability
        val isFullyTracking = augmentedImage.trackingState == TrackingState.TRACKING &&
                              augmentedImage.trackingMethod == AugmentedImage.TrackingMethod.FULL_TRACKING

        when {
            isFullyTracking -> {
                trackedImages[imageIndex] = augmentedImage
                
                // If a NEW image is detected while frozen on a different one, switch to new video
                if (isFrozen && frozenImageIndex != null && frozenImageIndex != imageIndex) {
                    Log.d(TAG, "🔄 New photo detected while frozen - switching to image_$imageIndex")
                    
                    // Hide the frozen video
                    activeCardViews[frozenImageIndex!!]?.let { oldCard ->
                        fadeOutVideo(frozenImageIndex!!) {
                            try {
                                activeVideoPlayers[frozenImageIndex!!]?.pause()
                            } catch (e: Exception) {}
                        }
                    }
                    
                    // Unfreeze and prepare for new video
                    isFrozen = false
                    frozenImageIndex = null
                    runOnUiThread {
                        freezeButton.alpha = 1.0f
                        freezeButton.setImageResource(android.R.drawable.ic_menu_view)
                    }
                }
                
                if (!activeCardViews.containsKey(imageIndex)) {
                    Log.d(TAG, "🎯 New target found: image_$imageIndex")
                    // Strong haptic feedback when target is detected!
                    performStrongHapticFeedback()
                    showLoading()
                    createVideoOverlay(imageIndex)
                } else {
                    // Ensure video is playing with fade in
                    activeVideoPlayers[imageIndex]?.let { player ->
                        if (!player.isPlaying) {
                            try {
                                player.start()
                                fadeInAudio(imageIndex, 300L) // Quick fade on resume
                                performHapticFeedback()
                            } catch (e: Exception) {}
                        }
                    }
                    // Check if CardView needs to be shown (only if not frozen on this one)
                    if (!isFrozen || frozenImageIndex == imageIndex) {
                        activeCardViews[imageIndex]?.let { cardView ->
                            if (isVideoVisible[imageIndex] != true) {
                                // Fade back in
                                isVideoVisible[imageIndex] = true
                                runOnUiThread {
                                    cardView.alpha = 0f
                                    cardView.scaleX = 0.9f
                                    cardView.scaleY = 0.9f
                                    cardView.visibility = View.VISIBLE
                                    cardView.animate()
                                        .alpha(1f)
                                        .scaleX(1f)
                                        .scaleY(1f)
                                        .setDuration(200L)
                                        .start()
                                }
                            }
                        }
                    }
                }
                showVideoPlaying()
            }
            
            augmentedImage.trackingState == TrackingState.PAUSED -> {
                // Photo moved away - fade out with audio (unless frozen on this video)
                if (isFrozen && frozenImageIndex == imageIndex) {
                    // Keep playing when frozen - user can relax!
                    Log.d(TAG, "🔒 Photo moved but video is frozen - continuing playback")
                } else if (isVideoVisible[imageIndex] == true) {
                    fadeOutVideo(imageIndex) {
                        try {
                            activeVideoPlayers[imageIndex]?.pause()
                        } catch (e: Exception) {}
                    }
                    showScanning()
                }
            }
            
            augmentedImage.trackingState == TrackingState.STOPPED -> {
                trackedImages.remove(imageIndex)
                // Photo completely gone - fade out with audio (unless frozen)
                if (isFrozen && frozenImageIndex == imageIndex) {
                    // Keep playing when frozen
                    Log.d(TAG, "🔒 Photo tracking stopped but video is frozen - continuing")
                } else if (isVideoVisible[imageIndex] == true) {
                    fadeOutVideo(imageIndex) {
                        try {
                            activeVideoPlayers[imageIndex]?.pause()
                        } catch (e: Exception) {}
                    }
                    showScanning()
                }
            }
        }
    }

    private fun pauseVideoWithFade(imageIndex: Int) {
        val player = activeVideoPlayers[imageIndex] ?: return
        val cardView = activeCardViews[imageIndex] ?: return
        
        if (player.isPlaying && isVideoVisible[imageIndex] == true) {
            // Fade out audio and video, then pause
            fadeOutVideo(imageIndex) {
                try {
                    player.pause()
                } catch (e: Exception) {}
            }
        } else if (isVideoVisible[imageIndex] == true) {
            // Just hide immediately if not playing
            isVideoVisible[imageIndex] = false
            runOnUiThread {
                cardView.visibility = View.GONE
            }
        }
    }

    private fun createVideoOverlay(imageIndex: Int) {
        val videoPath = videoPaths?.getOrNull(imageIndex) ?: return

        Log.d(TAG, "🎬 Creating video with Polaroid frame: $videoPath")

        val density = resources.displayMetrics.density
        val cornerRadiusPx = CORNER_RADIUS_DP * density
        val borderWidthPx = (BORDER_WIDTH_DP * density).toInt()

        // Create CardView for Polaroid-style rounded frame
        val cardView = CardView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            radius = cornerRadiusPx
            cardElevation = 8f * density  // Subtle shadow
            setCardBackgroundColor(Color.WHITE)  // White Polaroid border
            visibility = View.GONE
            // Content padding creates the white border effect
            setContentPadding(borderWidthPx, borderWidthPx, borderWidthPx, borderWidthPx)
        }

        // Create TextureView for video inside the card
        val textureView = TextureView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            // Clip to rounded corners
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, cornerRadiusPx * 0.7f)
                }
            }
            clipToOutline = true
        }

        cardView.addView(textureView)

        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                try {
                    val mediaPlayer = MediaPlayer().apply {
                        setDataSource(videoPath)
                        setSurface(Surface(surface))
                        isLooping = true
                        // Start with volume at 0 for fade-in effect
                        setVolume(0f, 0f)
                        prepare()
                        start()
                    }

                    Log.d(TAG, "▶️ Video started: ${mediaPlayer.videoWidth}x${mediaPlayer.videoHeight}")
                    lastVisibleTime[imageIndex] = System.currentTimeMillis()
                    activeVideoPlayers[imageIndex] = mediaPlayer
                    currentVolumes[imageIndex] = 0f
                    isVideoVisible[imageIndex] = true

                    // Play cinematic unfold animation with audio fade-in
                    playCinematicUnfold(cardView, imageIndex)

                } catch (e: Exception) {
                    Log.e(TAG, "❌ Video error: ${e.message}")
                    hideLoading()
                }
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                volumeAnimators[imageIndex]?.cancel()
                activeVideoPlayers[imageIndex]?.release()
                return true
            }
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
        }

        rootLayout.addView(cardView)
        activeCardViews[imageIndex] = cardView
        activeVideoViews[imageIndex] = textureView
    }

    private fun updateVideoPositions(frame: com.google.ar.core.Frame) {
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) return

        val projectionMatrix = FloatArray(16)
        val viewMatrix = FloatArray(16)
        camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100f)
        camera.getViewMatrix(viewMatrix, 0)

        val screenWidth = sceneView.width.toFloat()
        val screenHeight = sceneView.height.toFloat()

        trackedImages.forEach { (imageIndex, augmentedImage) ->
            // Skip position updates for frozen video - it stays centered
            if (isFrozen && frozenImageIndex == imageIndex) {
                return@forEach
            }
            
            val isFullyTracking = augmentedImage.trackingState == TrackingState.TRACKING &&
                                  augmentedImage.trackingMethod == AugmentedImage.TrackingMethod.FULL_TRACKING
            
            if (!isFullyTracking) {
                // Photo moved away - fade out video (unless frozen)
                if (!(isFrozen && frozenImageIndex == imageIndex) && isVideoVisible[imageIndex] == true) {
                    fadeOutVideo(imageIndex) {
                        try {
                            activeVideoPlayers[imageIndex]?.pause()
                        } catch (e: Exception) {}
                    }
                }
                return@forEach
            }

            val cardView = activeCardViews[imageIndex] ?: return@forEach
            val textureView = activeVideoViews[imageIndex] ?: return@forEach
            val mediaPlayer = activeVideoPlayers[imageIndex] ?: return@forEach

            val imagePose = augmentedImage.centerPose
            val halfWidth = augmentedImage.extentX / 2f
            val halfHeight = augmentedImage.extentZ / 2f

            val corners = arrayOf(
                floatArrayOf(-halfWidth, 0f, -halfHeight),
                floatArrayOf(halfWidth, 0f, -halfHeight),
                floatArrayOf(halfWidth, 0f, halfHeight),
                floatArrayOf(-halfWidth, 0f, halfHeight)
            )

            val screenCorners = corners.mapNotNull { localCorner ->
                val worldCorner = imagePose.transformPoint(localCorner)
                val worldPos = floatArrayOf(worldCorner[0], worldCorner[1], worldCorner[2], 1f)
                worldToScreen(worldPos, viewMatrix, projectionMatrix, screenWidth, screenHeight)
            }

            if (screenCorners.size == 4) {
                val minX = screenCorners.minOf { it[0] }
                val maxX = screenCorners.maxOf { it[0] }
                val minY = screenCorners.minOf { it[1] }
                val maxY = screenCorners.maxOf { it[1] }

                val centerX = (minX + maxX) / 2f
                val centerY = (minY + maxY) / 2f
                
                val isOnScreen = maxX > 0 && minX < screenWidth && maxY > 0 && minY < screenHeight

                if (isOnScreen) {
                    val imageScreenWidth = (maxX - minX).toInt().coerceIn(50, screenWidth.toInt())
                    val imageScreenHeight = (maxY - minY).toInt().coerceIn(50, screenHeight.toInt())
                    val leftMargin = (centerX - imageScreenWidth / 2f).toInt()
                    val topMargin = (centerY - imageScreenHeight / 2f).toInt()

                    runOnUiThread {
                        // Position the CardView (which contains the TextureView)
                        val params = cardView.layoutParams as FrameLayout.LayoutParams
                        params.width = imageScreenWidth
                        params.height = imageScreenHeight
                        params.leftMargin = leftMargin
                        params.topMargin = topMargin
                        cardView.layoutParams = params
                        
                        // Set pivot for animations based on actual size
                        cardView.pivotX = imageScreenWidth / 2f
                        cardView.pivotY = imageScreenHeight / 2f
                        
                        // Show card if not visible
                        if (isVideoVisible[imageIndex] != true && cardView.visibility != View.VISIBLE) {
                            // Fade back in
                            isVideoVisible[imageIndex] = true
                            cardView.alpha = 0f
                            cardView.scaleX = 0.9f
                            cardView.scaleY = 0.9f
                            cardView.visibility = View.VISIBLE
                            cardView.animate()
                                .alpha(1f)
                                .scaleX(1f)
                                .scaleY(1f)
                                .setDuration(200L)
                                .start()
                        }
                        
                        if (!mediaPlayer.isPlaying) {
                            try {
                                val lastVisible = lastVisibleTime[imageIndex] ?: 0L
                                if (System.currentTimeMillis() - lastVisible > VIDEO_RESET_THRESHOLD_MS) {
                                    mediaPlayer.seekTo(0)
                                }
                                mediaPlayer.start()
                                fadeInAudio(imageIndex, 300L)
                            } catch (e: Exception) {}
                        }
                        lastVisibleTime[imageIndex] = System.currentTimeMillis()
                    }
                } else {
                    // Photo moved off screen - fade out
                    if (isVideoVisible[imageIndex] == true) {
                        fadeOutVideo(imageIndex) {
                            try {
                                activeVideoPlayers[imageIndex]?.pause()
                            } catch (e: Exception) {}
                        }
                    }
                }
            } else {
                // Not enough corners visible
                if (isVideoVisible[imageIndex] == true) {
                    fadeOutVideo(imageIndex) {
                        try {
                            activeVideoPlayers[imageIndex]?.pause()
                        } catch (e: Exception) {}
                    }
                }
            }
        }
    }

    private fun worldToScreen(
        worldPos: FloatArray,
        viewMatrix: FloatArray,
        projMatrix: FloatArray,
        screenWidth: Float,
        screenHeight: Float
    ): FloatArray? {
        val viewPos = FloatArray(4)
        android.opengl.Matrix.multiplyMV(viewPos, 0, viewMatrix, 0, worldPos, 0)

        val clipPos = FloatArray(4)
        android.opengl.Matrix.multiplyMV(clipPos, 0, projMatrix, 0, viewPos, 0)

        if (clipPos[3] <= 0f) return null

        val ndcX = clipPos[0] / clipPos[3]
        val ndcY = clipPos[1] / clipPos[3]

        val screenX = (ndcX + 1f) / 2f * screenWidth
        val screenY = (1f - ndcY) / 2f * screenHeight

        return floatArrayOf(screenX, screenY)
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    override fun onPause() {
        super.onPause()
        // Cancel all animations
        volumeAnimators.values.forEach { it.cancel() }
        activeVideoPlayers.values.forEach { try { it.pause() } catch (e: Exception) {} }
    }

    override fun onDestroy() {
        super.onDestroy()
        isFrozen = false
        frozenImageIndex = null
        volumeAnimators.values.forEach { it.cancel() }
        volumeAnimators.clear()
        activeVideoPlayers.values.forEach { try { it.release() } catch (e: Exception) {} }
        activeVideoPlayers.clear()
        activeVideoViews.clear()
        activeCardViews.clear()
        trackedImages.clear()
        lastVisibleTime.clear()
        currentVolumes.clear()
        isVideoVisible.clear()
    }
}
