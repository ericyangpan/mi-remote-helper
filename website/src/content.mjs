export const project = {
  name: "Mi Remote Helper",
  repository: "https://github.com/ericyangpan/mi-remote-helper",
  version: "v1.0.0",
  download:
    "https://github.com/ericyangpan/mi-remote-helper/releases/download/v1.0.0/MiRemoteHelper-v1.0.0-arm64.zip",
};

export const languages = {
  en: {
    lang: "en",
    path: "/",
    other: "/zh/",
    otherLabel: "简体中文",
    screenshot: "en",
    title: "Mi Remote Helper — Your Xiaomi remote, now for your Mac",
    description:
      "Use the microphone on your Xiaomi Remote 2 Pro for WeChat voice input on Mac. Customize remote buttons with a native, open-source macOS app.",
    nav: ["Features", "Get started", "GitHub"],
    skip: "Skip to content",
    eyebrow: "A native Mac app. A new life for your remote.",
    headline: ["Your remote.", "Now for your Mac."],
    intro:
      "Turn your Xiaomi remote into a microphone and a set of shortcuts. Hold to speak. Release to finish. Keep your hands where they are.",
    download: "Download for Mac",
    source: "Explore on GitHub",
    compatibility: "Free & open source · Apple Silicon · macOS 14+",
    preview: "Meet your remote’s other side.",
    previewNote: "A familiar little device. A few new possibilities.",
    tabs: ["Voice input", "Button mapping"],
    screenshotAlt: [
      "Mi Remote Helper voice input window in English",
      "Mi Remote Helper button mapping window in English",
    ],
    previewCaption:
      "Actual app screenshots. Available in English and Simplified Chinese.",
    featuresEyebrow: "Small device. Useful details.",
    featuresTitle: "More than a remote.",
    features: [
      [
        "01",
        "A microphone, at hand.",
        "No microphone on your desktop Mac? Use the one in your remote. Mi Remote Helper sends its audio to WeChat Input, which turns your words into text.",
        "mic",
      ],
      [
        "02",
        "Your buttons. Your habits.",
        "Give 12 buttons their own short, double and long press actions. Set global shortcuts or tailor them to an app. The voice button stays dedicated to dictation.",
        "keys",
      ],
      [
        "03",
        "A little more control.",
        "Adjust microphone gain, try whisper mode, and see the input level. Keep your virtual microphone selected when headphones connect or disconnect.",
        "sliders",
      ],
    ],
    mappingTitle: "Make every button yours.",
    mappingNote: "Short, double and long press. Global or app-specific.",
    workflowEyebrow: "The simplest part",
    workflowTitle: "Hold. Speak. Release.",
    workflow: [
      "Hold the voice button",
      "Speak into your remote",
      "Release to finish",
    ],
    workflowNote:
      "Focus a text field first. Your input method handles recognition.",
    setupEyebrow: "A few things to connect",
    setupTitle: "Make yourself heard.",
    setupIntro: "Set it up once. Then keep your remote nearby.",
    steps: [
      [
        "Pair your remote",
        "Connect a Xiaomi Bluetooth Remote 2 Pro (RC003) in your Mac’s Bluetooth settings.",
      ],
      [
        "Install the audio bridge",
        "Install BlackHole 2ch separately. It carries the remote’s sound into your input method.",
      ],
      [
        "Match your voice shortcut",
        "Choose Fn / Globe or Left Control in both apps. In WeChat Input, use “tap to start, tap again to stop”.",
      ],
      [
        "Allow access, then speak",
        "Grant Bluetooth and Accessibility access. Button mapping also needs Input Monitoring. Focus a text field, then hold the voice button.",
      ],
    ],
    blackhole: "Get BlackHole 2ch",
    guide: "Read the full setup guide",
    requirementsTitle: "Before you begin",
    requirements: [
      "Apple Silicon Mac · macOS 14 or later",
      "Xiaomi Remote 2 Pro · model RC003",
      "BlackHole 2ch or compatible MiRemoteV",
      "WeChat Input with voice input enabled",
    ],
    requirementsNote:
      "Intel Macs and other remote models are not supported. Other input methods have not been validated.",
    faqTitle: "Good to know.",
    faqs: [
      [
        "Does it recognize speech itself?",
        "No. Mi Remote Helper delivers microphone audio and triggers your chosen shortcut. WeChat Input performs speech recognition.",
      ],
      [
        "Why is BlackHole needed?",
        "macOS needs an audio device that an input method can listen to. BlackHole is the virtual connection between your remote’s microphone and WeChat Input. Install it separately; it is not bundled with this app.",
      ],
      [
        "Can I use it in different apps?",
        "Yes. Focus a text field before speaking. Button mappings can be global or app-specific, with import and export for portable configurations. The app does not move text-field focus for you.",
      ],
      [
        "What does whisper mode do?",
        "It disables audio smoothing and keeps a separate gain setting. Recognition still depends on your input method; improved whisper recognition is not guaranteed.",
      ],
      [
        "Does the app record or upload audio?",
        "Mi Remote Helper does not record or upload audio. Your input method handles recognition under its own privacy policy.",
      ],
    ],
    closing: "Give your remote a new role.",
    closingNote: "One small helper for the Mac you already use.",
    builtBy: "Pan YANG",
    license: "GPL-3.0 · Source available",
    credits: "Product imagery belongs to Xiaomi or its rights holders.",
    notices: "Credits & licenses",
    notFound: "This page isn’t here.",
    back: "Back to the homepage",
  },
  zh: {
    lang: "zh-CN",
    path: "/zh/",
    other: "/",
    otherLabel: "English",
    screenshot: "zh-CN",
    title: "Mi Remote Helper — 让小米遥控器成为 Mac 的麦克风",
    description:
      "用小米蓝牙遥控器 2 Pro 的麦克风在 Mac 上进行微信语音输入，自定义遥控器按键。原生 macOS 应用，免费开源。",
    nav: ["功能", "开始使用", "GitHub"],
    skip: "跳到正文",
    eyebrow: "原生 Mac 应用，遥控器的新用法。",
    headline: ["不止遥控。", "让 Mac 听见你。"],
    intro:
      "把小米遥控器变成麦克风和快捷键。按住说话，松开结束，让手边的小设备多做一点。",
    download: "下载 Mac 版",
    source: "在 GitHub 探索",
    compatibility: "免费开源 · Apple Silicon · macOS 14+",
    preview: "熟悉的遥控器，多一种可能。",
    previewNote: "从说话到操作，都在手边。",
    tabs: ["语音输入", "按键映射"],
    screenshotAlt: [
      "Mi Remote Helper 中文语音输入窗口",
      "Mi Remote Helper 中文按键映射窗口",
    ],
    previewCaption: "应用实拍截图。支持简体中文与 English。",
    featuresEyebrow: "小设备，也有好细节。",
    featuresTitle: "让它多做一点。",
    features: [
      [
        "01",
        "手边，就是麦克风。",
        "台式 Mac 没有麦克风？遥控器有。Mi Remote Helper 将它的声音送到微信输入法，由输入法把你说的话变成文字。",
        "mic",
      ],
      [
        "02",
        "按键，按你的习惯来。",
        "12 个按键，分别设置短按、双击和长按。全局使用，也能为单个应用定制；语音键始终用于语音输入。",
        "keys",
      ],
      [
        "03",
        "收音，再多一点掌控。",
        "调整麦克风增益，尝试耳语模式，查看输入电平。连接或摘下耳机时，也能保持虚拟麦克风作为输入。",
        "sliders",
      ],
    ],
    mappingTitle: "每个按键，都按你的习惯来。",
    mappingNote: "短按、双击、长按，全局或按应用配置。",
    workflowEyebrow: "用起来，其实很简单。",
    workflowTitle: "按住，说话，松开。",
    workflow: ["按住语音键", "对着遥控器说话", "松开，结束输入"],
    workflowNote: "先把焦点放在文本框中，语音识别由输入法完成。",
    setupEyebrow: "连接好，就可以开始。",
    setupTitle: "让你的声音接上 Mac。",
    setupIntro: "设置一次，把遥控器放在手边。",
    steps: [
      ["配对遥控器", "在 Mac 蓝牙设置中，连接小米蓝牙遥控器 2 Pro（RC003）。"],
      [
        "安装音频桥接",
        "单独安装 BlackHole 2ch，它会把遥控器的声音送到输入法。",
      ],
      [
        "匹配语音快捷键",
        "在两个应用中选择相同的 Fn／地球键或左 Ctrl。微信输入法使用“按一下开始，再按一下结束”的模式。",
      ],
      [
        "完成授权，开始说话",
        "允许蓝牙和辅助功能权限；按键映射还需要输入监控。先点击文本框，再按住语音键说话。",
      ],
    ],
    blackhole: "获取 BlackHole 2ch",
    guide: "阅读完整安装说明",
    requirementsTitle: "开始前，你需要",
    requirements: [
      "Apple Silicon Mac · macOS 14 或更新版本",
      "小米蓝牙遥控器 2 Pro · RC003",
      "BlackHole 2ch 或兼容的 MiRemoteV",
      "已启用语音输入的微信输入法",
    ],
    requirementsNote: "不支持 Intel Mac 和其他遥控器型号。其他输入法尚未验证。",
    faqTitle: "你可能还想知道。",
    faqs: [
      [
        "它会自己识别语音吗？",
        "不会。Mi Remote Helper 提供麦克风声音，并触发你选择的快捷键；语音识别由微信输入法完成。",
      ],
      [
        "为什么需要 BlackHole？",
        "输入法需要从 macOS 音频设备获取声音。BlackHole 是遥控器麦克风和微信输入法之间的虚拟连接，需要单独安装，本应用不附带它的安装器。",
      ],
      [
        "可以在不同应用里使用吗？",
        "可以，先将焦点放在文本框中再说话。按键映射支持全局和按应用配置，也可以导入、导出。应用不会替你移动文本框焦点。",
      ],
      [
        "耳语模式有什么作用？",
        "它会关闭音频平滑，并保存独立的增益设置。识别效果仍取决于输入法，不保证提高耳语的识别成功率。",
      ],
      [
        "它会录音或上传声音吗？",
        "Mi Remote Helper 不录音、不上传声音。输入法负责语音识别，其隐私行为以输入法自己的政策为准。",
      ],
    ],
    closing: "给遥控器一个新角色。",
    closingNote: "一个小小的 helper，让你手边的 Mac 更好用。",
    builtBy: "Pan YANG",
    license: "GPL-3.0 · 代码开源",
    credits: "产品图片归小米或其权利人所有。",
    notices: "致谢与许可证",
    notFound: "这个页面不在这里。",
    back: "回到首页",
  },
};
