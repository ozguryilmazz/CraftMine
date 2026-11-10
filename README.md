# CraftMine

Godot 4.5 (GDScript) ile yazılmış, dokunmatik kontrollü, voxel tabanlı mobil sandbox oyunu.
4 haneli oda koduyla çok oyunculu oynanır; APK, GitHub Actions ile otomatik derlenir.

## Özellikler

- **Sonsuz dünya:** 16×16×64 chunk'lar, Perlin gürültüsüyle arazi, deniz, kumsal ve ağaçlar. Chunk üretimi ve mesh'leme arka plan iş parçacıklarında yapılır.
- **Bloklar:** Çim, Toprak, Taş, Tahta, Kütük, Yaprak, Su, Meşale (ışık verir), Kum. Yaratıcı mod: bloklar sınırsızdır.
- **Kontroller (mobil):** sol altta joystick, sağ altta zıplama, ekranı sürükleyerek bakış, **basılı tut = kır** (çatlak animasyonuyla, bloğun sertliğine göre), **dokun = yerleştir**, altta hotbar, sağ üstte 1./3. şahıs geçişi.
- **Kontroller (PC):** WASD + fare, sol tık basılı tut = kır, sağ tık yerleştir, 1–9 / tekerlek ile blok seç, `V` veya `F5` kamera, `Esc` menü.
- **Çok oyunculu:** "Sunucu Kur" 4 haneli kod üretir, diğer oyuncu "Oyuna Katıl" ile aynı kodu girer. Oyuncu konumları ve blok değişiklikleri Firebase Realtime Database üzerinden anlık eşitlenir; sonradan katılan oyuncu dünyanın güncel halini alır.
- **Güncelleme kontrolü:** Ana menüdeki buton (ve açılışta sessiz kontrol) GitHub Releases'teki en son sürüme bakar, yenisi varsa APK indirme bağlantısını açar.
- **Kayıt:** Tek oyunculu / host dünyası cihazda otomatik kaydedilir.

## Proje yapısı

```
project.godot, export_presets.cfg, version.json
scenes/            main_menu.tscn, game.tscn
scripts/
  session.gd       oturum durumu, ayarlar, dünya kaydı (autoload)
  game.gd          oyun sahnesi: dünya + oyuncu + arayüz + eşitleme
  player.gd        hareket, voxel çarpışması, kamera
  player_model.gd  oyuncu modeli (3. şahıs ve diğer oyuncular)
  updater.gd       güncelleme kontrolü
  world/           blocks, atlas (dokular), world_gen, chunk_mesher, world
  net/             firebase_config, http_queue, sse_stream, network (autoload "Net")
  ui/              main_menu, hud (dokunmatik kontroller + hotbar)
firebase/database.rules.json   veritabanı güvenlik kuralları
android/debug.keystore         CI'ın kullandığı sabit imza anahtarı
.github/workflows/build-apk.yml
tests/             geliştirme araçları (APK'ya dahil edilmez)
```

## Firebase kurulumu (çok oyunculu için gerekli)

1. Firebase Console → **Authentication → Sign-in method → Anonymous** girişini etkinleştirin.
2. **Proje ayarları → Genel → Web API Key** değerini `scripts/net/firebase_config.gd` içindeki `API_KEY` sabitine yazın.
3. **Realtime Database → Rules** sekmesine `firebase/database.rules.json` içeriğini yapıştırıp yayınlayın.

Bağlantıyı denemek için: `godot --headless --path . res://tests/net_test.tscn`

## Yeni sürüm yayınlama

1. `version.json` içindeki `version` (ve `version_code`) değerini artırın.
2. `main` dalına push edin. Workflow APK'yı derler, artifact olarak yükler ve `v<sürüm>` etiketiyle Release oluşturur.
   (Alternatif: `git tag v1.1.0 && git push --tags`.)
3. Eski sürümü kullanan oyuncular menüde güncelleme uyarısı görür.

Aynı sürüm numarasıyla yapılan push'lar mevcut Release'in APK'sını günceller.

## Bilinen sınırlar

- Su akmaz (sabit su blokları), mağara / mob / zanaat (crafting) yoktur.
- Çok oyunculu veri Firebase üzerinden geçer (gerçek P2P değildir); gecikme tipik olarak 100–300 ms'dir.
- APK herkese açık bir debug anahtarıyla imzalanır; Play Store'da yayınlamak için kendi anahtarınızı kullanın.
