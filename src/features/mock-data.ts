export const events = [
      {
        id: 'ev1',
        time: '日曜 9:00',
        zone: '竹橋',
        cafe: '丸の内ベーカリー',
        vibe: 'おしゃべりペース',
        womenOnly: true,
        category: ['women', 'cafe', 'beginner'],
        spotsLeft: 2,
        maxMembers: 4,
        joined: false,
        host: { name: 'みゆ', emoji: '🥐', ig: '@miyu_morning', bio: '朝ランとパン屋めぐり / 初心者歓迎です🫧', tags: ['淡色ウェア', '抹茶ラテ派', 'ゆっくり1周'] }
      },
      {
        id: 'ev2',
        time: '水曜 19:30',
        zone: '桜田門',
        cafe: '日比谷スタンドコーヒー',
        vibe: '写真メイン',
        womenOnly: false,
        category: ['cafe'],
        spotsLeft: 3,
        maxMembers: 5,
        joined: false,
        host: { name: 'れん', emoji: '☕', ig: '@ren_tokyo_run', bio: '仕事終わりの夜ランゆる部。タイム見ません！', tags: ['夜景ラン', 'デジカメ好き', '20代中心'] }
      },
      {
        id: 'ev3',
        time: '土曜 8:30',
        zone: '半蔵門',
        cafe: '麹町ドーナツカフェ',
        vibe: '初心者だけ',
        womenOnly: true,
        category: ['women', 'beginner', 'cafe'],
        spotsLeft: 1,
        maxMembers: 3,
        joined: false,
        host: { name: 'あおい', emoji: '🎀', ig: '@aoi_pilates_run', bio: '普段はピラティス派。歩き混じりでもOK！', tags: ['女性限定', 'ご褒美ドーナツ', '1周ゆるジョグ'] }
      }
    ];

    export const zones = [
      { id: 'takebashi', name: '竹橋', x: 54, y: 15, count: 4, runners: ['みゆ 🥐', 'かな 🌷', 'さら 🎧', 'ゆい ☕'] },
      { id: 'hirakawamon', name: '平川門', x: 76, y: 27, count: 2, runners: ['りこ 🍓', 'はる 🧃'] },
      { id: 'otemachi', name: '大手町', x: 83, y: 50, count: 3, runners: ['れん ☕', 'もも 🍑', 'たく 👟'] },
      { id: 'nijubashi', name: '二重橋前', x: 76, y: 74, count: 2, runners: ['えま 🧸', 'のあ 🌼'] },
      { id: 'sakuradamon', name: '桜田門', x: 53, y: 86, count: 3, runners: ['あおい 🎀', 'ひな 🍋', 'すず 🫧'] },
      { id: 'iwatabashi', name: '祝田橋', x: 26, y: 74, count: 1, runners: ['れい 🌿'] },
      { id: 'hanzomon', name: '半蔵門', x: 18, y: 49, count: 2, runners: ['なな 🍩', 'みさ 🍒'] },
      { id: 'chidorigafuchi', name: '千鳥ヶ淵', x: 27, y: 26, count: 2, runners: ['こころ 🌸', 'ゆめ ☁️'] }
    ];

    export const otsurunPeople = [
      { id: 'p1', name: 'みゆ', emoji: '🥐', context: '日曜 9:00 竹橋ゆるランで一緒', ig: '@miyu_morning', theySent: true, sentStamps: [] as string[] },
      { id: 'p2', name: 'あおい', emoji: '🎀', context: '桜田門エリアですれ違い', ig: '@aoi_pilates_run', theySent: true, sentStamps: [] as string[] },
      { id: 'p3', name: 'かな', emoji: '🌷', context: '同じ時間帯に皇居をラン', ig: '@kana_asakatsu', theySent: false, sentStamps: [] as string[] }
    ];

    export const stampTypes = [
      { id: 'otsurun', label: 'おつラン！✨' },
      { id: 'asakatsu', label: '朝活えらい☀️' },
      { id: 'wear', label: 'ウェア可愛い🎀' },
      { id: 'again', label: 'また走ろ☕' }
    ];
