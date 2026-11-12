# CraftMine — proje durumu ve çalışma kuralları

Bu dosya projede açılan her yeni oturuma otomatik yüklenir. **Kodda yapılan her işlemden sonra bu dosya güncellenir** (kullanıcının 11 Kasım 2026 tarihli isteği): "Mevcut durum", "Sürüm geçmişi" ve gerekiyorsa diğer bölümler o işlemi yansıtmalı ve aynı commit'e girmelidir.

Kullanıcı Türkçe konuşur; yanıtlar Türkçe yazılır. Commit ve push işlemlerini Claude yapar (kullanıcı böyle istedi). Kod yorumları ve arayüz metinleri Türkçedir.

## Mevcut durum

- **Sürüm:** 1.16.0 (version_code 21). Son commit konusu: G2 — gündüz-gece döngüsü ve atmosfer.
- **Tamamlanan aşamalar:** 1–10 (aşağıdaki tabloya bakın) ve ilk telefon geri bildirimi düzeltmeleri.
- **Grafik yol haritası:** G0 (v1.14.0), G1 (v1.15.0) ve G2 (v1.16.0) tamamlandı. **Sıradaki iş G3** (güneş gölgeleri, yalnızca "yüksek" ayarda). **Telefon ölçümü (kullanıcı, 12 Kasım 2026, v1.15.0, Samsung A34):** üç kalite ayarında da 60 FPS (ekran yenileme sınırı), chunk yüklenirken takılma yok. Yani cihazda pay var; görüş mesafesi ve MSAA FPS'i düşürmüyor. Aşama 11 (çok oyunculu) grafiklerden sonraya kaldı.
- **Gerçek cihazda doğrulanmayanlar:** v1.16.0 gündüz-gece (renkler, gece parlaklığı), v1.12.1 düzeltmeleri, v1.13.0 envanter ekranı (dokunma, sürükle-bırak, sekmeler), boss'ların kendiliğinden doğması, çok oyunculu kodun tamamı, oyun içi güncelleme kontrolü.

## Proje

Dokunmatik kontrollü, Minecraft tarzı voxel oyun. Godot 4.5.1, GDScript, `gl_compatibility`, yatay ekran. Depo: `ozguryilmazz/CraftMine`, dal `main`.

- Her şey kodla kurulur: sahneler yalnızca kök düğüm + betik içerir; dokular ve simgeler çalışma anında üretilir (ikili görsel dosya yok).
- Arayüz elle çizilen `Control`'lerdir (`_draw` + elle isabet testi). `set_anchors_and_offsets_preset` kullanılır (`set_anchors_preset` boyutu 0 bırakır).
- Çok oyunculu: Firebase Realtime Database aktarıcı olarak kullanılır (REST + SSE, anonim giriş), 4 haneli oda kodu. Şu an yalnızca oyuncu konumları ve blok değişiklikleri eşitlenir.
- CI: `.github/workflows/build-apk.yml` `main`'e her push'ta APK derler ve `v<sürüm>` Release'i oluşturur/günceller. İmza depodaki `android/debug.keystore` ile yapılır.

### Önemli dosyalar

| Dosya | İçerik |
|---|---|
| `scripts/game.gd` | Oyun sahnesi: kırma/yerleştirme, düşen eşyalar, moblar, dövüş, sandıklar, can/ölüm, kayıt, ağ |
| `scripts/player.gd` | Oyuncu fiziği, kamera, elde tutma, düşme sinyali, sudan çıkış |
| `scripts/player_stats.gd` | Can, statlar, level/XP, iksir etkileri, ölüm cezası (tüm sayılar sabitlerde) |
| `scripts/items.gd` | Eşya kayıt defteri; RPG eşyaları `DEFS` tablosunda (hasar, can, dayanıklılık, level, fiyat alanı) |
| `scripts/inventory.gd` | 36 yuva + 4 ekipman yuvası; her yuva (kimlik, adet, dayanıklılık) |
| `scripts/recipes.gd` | Şekilli tarifler, fırın |
| `scripts/loot.gd`, `scripts/loot_chest.gd` | Drop tabloları, sandık zarı, sandık nesnesi |
| `scripts/mobs/mob_db.gd`, `scripts/mobs/mob.gd` | 13 mobun değerleri; model, fizik, yapay zeka |
| `scripts/ui/hud.gd` | Dokunmatik girdi, hotbar, can/XP çubukları, level butonu, iksir listesi, boss çubuğu |
| `scripts/ui/inventory_ui.gd` | Tam ekran envanter: solda tarif listesi / envanter sekmeleri, sağda üretim (ya da fırın, sandık) / ekipman sekmeleri, altta hotbar |
| `scripts/ui/stats_ui.gd` | Karakter ekranı (stat puanı dağıtma) |
| `scripts/world/*` | Chunk üretimi, mesh, atlas (blok ve eşya simgeleri), dünya değişiklikleri |
| `scripts/net/*`, `firebase/database.rules.json` | Ağ katmanı ve Firebase kuralları |
| `tests/` | `shot.tscn` (oyun içi senaryo + ekran görüntüsü), `items_test.gd`, `stats_test.gd`, `loot_test.gd`, `net_test.tscn` |

## Çalışma yöntemi

- **Godot:** `~/Desktop/Godot_v4.5.1-stable_win64.exe` (Git Bash'te `G="$HOME/Desktop/Godot_v4.5.1-stable_win64.exe"`).
- **Yeni `class_name` eklenince** önce `"$G" --headless --path . --import` çalıştırılır (sınıf önbelleği).
- **Kural testleri:** `"$G" --headless --path . -s res://tests/items_test.gd` (aynı şekilde `stats_test`, `loot_test`). Çıktıda `SONUC: 0 hata` beklenir.
- **Oyun senaryosu:** `timeout 260 "$G" --path . res://tests/shot.tscn -- --out=<klasör> --touch` (yaklaşık 4 dakika; arka planda çalıştırılır). PNG'ler okunarak kontrol edilir. `--menu` yalnızca menü görüntüsü alır.
- **Çok dosyalı değişiklikler** geçici klasöre yazılan Python yama betikleriyle yapılır (önce tüm eşleşmeler doğrulanır, sonra yazılır). Betikteki girinti dosyadakiyle birebir aynı olmalı.
- **Sürüm çıkarma:** `version.json`, `project.godot` (`config/version`) ve `export_presets.cfg` (`version/code`, `version/name`) birlikte yükseltilir; commit + push; CI `curl https://api.github.com/repos/ozguryilmazz/CraftMine/actions/runs?per_page=1` ile arka planda `until` döngüsüyle beklenir (`gh` kurulu değil).
- **Commit mesajları** Türkçe, sonunda `Co-Authored-By` satırı.

### Bu bilgisayardaki kısıtlar

- **Avast HTTPS taraması** sertifikaları yeniden imzaladığı için Godot'nun ağ kodu bu PC'de TLS hatası verir. Çok oyunculu ve güncelleme kontrolü burada test edilemez; telefonlar etkilenmez. TLS doğrulamasını gevşetmek reddedildi, **etrafından dolanılmamalıdır**.
- Dokunmatikte her dokunuş hem `InputEventScreenTouch` (HUD `_input`) hem de taklit fare olayı (arayüz `_gui_input`) olarak gelir. Üst üste binen butonlarda ikisi de tetiklenebilir; HUD'daki `_ignored` ve `game.ui_closed_frame` bunu önler. Bu davranış PC testinde yeniden üretilemez.
- `tests/shot.gd` zamanlamaya duyarlıdır: rastgele mob doğması ve eşya toplama sonuçları oynatabilir. Bir adım beklenmedik sonuç verirse önce testin kendisinden şüphelenin.

## RPG kuralları (mns2026.xlsx + kullanıcı kararları)

Kaynaklar kullanıcının `Downloads` klasöründeki `mns2026.xlsx` ve `Yeni Metin Belgesi (2).txt` dosyalarıdır. Çelişkide txt (daha yeni) ve aşağıdaki kararlar geçerlidir.

**Oyuncu**
- Başlangıç canı 30 (aktif moblar 2 vuruşta öldürsün diye). Her sağlık puanı +2 can.
- Saldırı: her puan +1 hasar. Hız: her puan +%5. Zeka: her puan +%2 kritik ihtimali, kritikte saldırı gücünün %10'u × zeka kadar ek hasar.
- Vuruş sekmesi: başlangıçta %20, her zeka puanı 1 puan düşürür. Sekme hasar vermez ama kılıcı yıpratır ve mobu kışkırtır.
- Level 15 üst sınır; XP gereksinimleri 100, 120, 130, 140, 200, 220, 240, 260, 280, 400, 450, 500, 600, 700, 1000; puanlar 3'er, 5/10/15. levellerde 5 (toplam 51).
- **Ölüm:** tüm envanter ve ekipman silinir, XP ve level 0'a düşer, her stattan 1 puan düşer (dağıtılan puan 0'ın altına inmez). Stat puanı yalnızca bir levele **ilk kez** ulaşıldığında verilir (`best_level`); ölüp tekrar çıkan oyuncu aynı puanları toplayamaz.
- Can yalnızca yemekle dolar: her et saniyede 2 can, 5 sn (toplam 10); çürük zombi eti 2 sn (toplam 4). Süreleri Claude belirledi. Kendiliğinden yenilenme yok. İleride daha hızlı yiyecekler eklenecek (`rate` alanı hazır).

**Eşyalar**
- Kılıçlar (hasar / dayanıklılık / gereken level): tahta 4/10/0, taş 6/15/2, demir 8/20/4, altın 10/25/6, elmas 15/40/9, nether 25/60/12. Level sınırlarını Claude önerdi. Level yetmezse kılıç bonus vermez, yıpranmaz ve üretilemez. Nether üretilemez, yalnızca ganimet.
- Zırh ve kalkan (can / dayanıklılık): kafalık 2/10, göğüslük 5/15, pantolon+ayakkabı (tek parça) 8/15, tahta kalkan 4/15, demir 8/25, elmas 10/35. Yalnızca moblardan düşer. Can doğrudan eklenir; hasar azaltmaz. Mob her vurduğunda takılı tüm parçalar 1 yıpranır (düşme hasarı yıpratmaz).
- Dayanıklılık değerleri bilerek düşük bırakıldı (kullanıcı: "tahta kılıçla zombiye saldırılamayacağını oyuncu anlar").
- İksirler: +3, 5 dakika, aynı iksir süreyi yeniler, ölünce biter.
- Ölümsüzlük totemi: envanterdeyken ölümü bir kez engeller, canı doldurur, ceza yok. Kral tacı şimdilik etkisiz.
- Balta, kazma, kürek silah değildir (1 hasar). Aletlerin dayanıklılığı yoktur.

**Moblar** (hepsi yakın dövüş; saldırı aralığı 1,2 sn)
- Pasif (tavuk 15 can/2 XP; domuz, inek, koyun 20/2): saldırmaz, vurulunca kaçar. Sık ve dağınık doğar, en fazla 12.
- Yarı pasif (kurt 60/7 atk/5 XP, arı 60/8/5, kızgın köylü 70/10/8, büyücü köylü 75/12/10): vurulunca kovalar, 16 blokta bırakır. 5'li grup, en fazla 10, 10 sn'de bir deneme. Gruptan yalnızca vurulan saldırır.
- Aktif (zombi 100/15/15, iskelet 110/15/16, creeper 130/20/18): 10 blokta fark eder, 28 bloğa kadar kovalar. 4'lü grup, en fazla 8, 16 sn'de bir deneme.
- Boss (golem 1000/50/200, dev örümcek 800/40/150): vurulmadan saldırmaz, 16 blok takip. Tek doğar, aynı anda en fazla 1; 45 sn'de bir %30 ihtimal (sıklığı Claude belirledi).
- **Güvenli bölge:** başlangıç noktasının 48 blok çevresinde aktif mob ve boss doğmaz (Claude ekledi, kullanıcı itiraz etmedi).
- Moblar kaydedilmez ve çok oyunculuda eşitlenmez.

**Ganimet sandığı**
- Eşya sayısı zincirleme: %80 ile 1., çıktıysa %50 ile 2., sonra %20, %10, %6, %1. Hiç çıkmazsa sandık düşmez.
- Eşyalar sütun ağırlıklarıyla (%60/30/20/10/5/1; aktif ve boss'ta ikinci sütun %40), aynı sütun tekrar etmeden seçilir. Tablodaki "taş" kırık taş olarak verilir.
- Sandık 10 sn'de yok olur. **Otomatik toplanmaz:** dokununca içeriği açılır, oyuncu istediği eşyayı ya da "Hepsini Al"ı seçer. Ekran açıkken süre işlemez.

**Envanter ekranı**
- Kullanıcı Minecraft Bedrock envanter ekranının düzenini örnek gösterdi: iki büyük panel, kenarlarda sekmeler, altta hotbar. Düzen ve işlev buna göre kuruldu; görseller (simgeler, yazı tipi) oyunun kendi çizimleridir, birebir kopyalanmaz.
- Sol sekmeler: "Tarifler" (yalnızca envanter ve çalışma masası ekranlarında; ızgaraya sığan tarifler, dokununca malzeme envanterden alınıp üretilir) ve "Envanter" (27 yuva). Sağ sekmeler: ekrana özgü içerik (üretim 2x2 / 3x3, fırın, sandık) ve "Ekipman".
- Varsayılan sol sekme tariflerdir; eşya sürüklemek için "Envanter" sekmesine geçilir ya da hotbar kullanılır.

**Diğer**
- Düşme hasarı: 3 bloğa kadar zararsız, sonrası blok başına 2 can; suya düşmek zararsız (Claude ekledi).
- Yanında ya da üstünde su olan blok kırılınca yeri suyla dolar; su akmaz.
- Para birimi **kakacoin**: `Items.DEFS` içinde `price` alanı ve kayıtta `coins` sayacı hazır, arayüzü ve dükkanı yok.

## Sürüm geçmişi

| Sürüm | İçerik |
|---|---|
| 1.0.0–1.3.1 | Voxel dünya, kırma/yerleştirme, envanter, crafting, fırın, çok oyunculu altyapı, güncelleme kontrolü, alet tutuşu |
| 1.3.2 | Aşama 1: eşya tablosu, yuva başı dayanıklılık, yeni kayıt biçimi |
| 1.4.0 | Aşama 2: can barı, hasar, ölüm cezası, yemek, düşme hasarı |
| 1.5.0 | Aşama 3: karakter ekranı, XP çubuğu, stat puanı dağıtma |
| 1.6.0 | Aşama 4: kılıçlar, sekme/kritik, level sınırı, tavuk |
| 1.7.0 | Aşama 5: domuz, inek, koyun; doğma düzeni |
| 1.8.0 | Aşama 6: yarı pasif ve aktif moblar, oyuncuya saldırı |
| 1.9.0 | Aşama 7: ganimet sandığı, drop tabloları, tüm RPG simgeleri |
| 1.10.0 | Aşama 8: ekipman yuvaları |
| 1.11.0 | Aşama 9: iksirler, totem |
| 1.12.0 | Aşama 10: boss'lar |
| 1.16.0 | G2: güneş doğudan batıya hareket eder, gece ay ışığı; gün doğumu/batımında turuncu gökyüzü ve sis; gökyüzünde kare güneş ve ay; gece daha aydınlık (ortam ışığı 0.12 → 0.34, mavimsi) |
| 1.15.0 | G1: köşe gölgesi — blokların birleştiği köşe ve diplerde yumuşak koyulaşma (tüm kalite ayarlarında açık; çizim maliyeti yok, yalnızca mesh kurma süresi) |
| 1.14.0 | G0: FPS sayacı (sol üstte), duraklatma menüsünde "Grafik: Düşük/Orta/Yüksek" ve "FPS Sayacı" butonları; ayar `user://settings.cfg` içinde saklanır |
| 1.13.1 | Düzeltme: envanter / çalışma masası kapatılınca 3. şahıstan 1. şahsa geçilmesi (X butonu HUD'daki görünüm butonunun üstündeydi ve aynı dokunuş ikisine de ulaşıyordu; HUD artık ekran açıkken ya da kapanırken başlayan dokunuşları yok sayıyor) |
| 1.13.0 | Envanter ekranı yeniden düzenlendi: tam ekran, kabartmalı iki panel, sekmeler, tarif listesinden hızlı üretim (malzemesi eksik tarifler kırmızı) |
| 1.12.1 | Telefon geri bildirimi: sudan çıkış, suyun dolması, dokunarak açılan sandık, kılıç üretiminde level sınırı, eldeki kılıcın hasar göstergesi |

## Grafik yol haritası (kullanıcı onayladı, 11 Kasım 2026)

Hedef: klasik voxel görünümü korunur; ışık, gölge, doku ve atmosfer kalitesi yükseltilir. Mimari değişmez, aşama aşama ilerlenir. Her aşama: kod → PC testi → yeni sürüm → kullanıcı telefonda dener → sonraki aşama. G0, G1 ve G2 bitti; G3–G9 başlamadı.

**Gökyüzü (G2'de kuruldu):** `game.gd` `_update_sky`. `t` = günün kesri (cihaz saatinden, `DAY_LENGTH` 720 sn; 0 gün doğumu, 0.25 öğle, 0.5 gün batımı, 0.75 gece yarısı), `h = sin(t·TAU)` güneş yüksekliği. Güneş yönü `(cos, h, 0.35)`; `_sun` (DirectionalLight3D) gündüz güneşten, gece karşıdaki aydan (enerji 0.16, mavimsi) aydınlatır, ışık yüksekliği en az 0.25. Gökyüzü/sis: `SKY_NIGHT` → `SKY_DAY`, ufka yakınken `SKY_DUSK` (ilk denemede zayıf karışım gri-mor çıktı; ağırlık 0.8'e çıkarıldı). `_sun_disc` / `_moon_disc` kameradan 300 birim uzakta, sisten etkilenmeyen kare levhalar. Hızlı test: `shot.tscn -- --sky` (`g2_t*.png`). G3'te gölge yönü bu `_sun`'dan gelir.

**Köşe gölgesi (G1'de kuruldu):** `ChunkMesher.build(d, nb)` artık 8 komşu alır (`World.NEIGHBORS` sırası: 4 yan + 4 çapraz). `_occupancy` 18×66×18 dolgulu doluluk dizisi kurar; her köşe için 3 komşuya bakılır (`_ao_off`), parlaklık `AO_CURVE = [0.3, 0.48, 0.68, 1.0]` ile yüz parlaklığına çarpılır (`_shade_ao`). Köşegen daha aydınlık köşe çiftinden geçirilir. Su yüzeylerine uygulanmaz. `set_block` sınırdaki blokta çapraz chunk'ı da yeniden mesh'ler. Eğri 0.5/0.68/0.84 iken gölge görünmüyordu; değerler bu yüzden koyu. PC'de mesh süresi chunk başına ~30–50 ms (iş parçacığında). Hızlı test: `shot.tscn -- --ao` (`g1_*.png`). `game.sky_time_override` (0.25 = öğle) testlerde gündüz görüntüsü almak için eklendi.

**Kalite ayarı (G0'da kuruldu):** `Session.quality` (0 düşük, 1 orta, 2 yüksek; varsayılan orta), `Session.show_fps` (varsayılan açık, ölçüm dönemi için), `Session.quality_changed` sinyali, `Session.render_distance()`. `game.gd` `_apply_quality()` ayarı uygular. Şu an ayarın etkisi: görüş mesafesi telefonda 3/4/5, bilgisayarda 4/6/8 chunk (orta = önceki değerler); yüksekte 2x MSAA. `World.set_render_distance()` çalışırken mesafeyi değiştirir. Sonraki aşamalar `Session.quality`'ye bakmalı. Hızlı test: `shot.tscn -- --gfx` (yaklaşık 25 sn; üç ayarı dolaşır, `g0_*.png` kaydeder).

**Kullanıcının kararları**
- Dokular **16×16 pikselde kalır**; ayrıntı ve varyasyon artırılır (32 piksele geçilmez).
- Sallanan çim için **yeni bir uzun çim bitkisi bloğu** eklenir: dekoratif, içinden geçilir, **kırılabilir ama bir şey düşürmez**.
- Gerçek zamanlı gölge **ayarlarda "yüksek kalite" seçeneğiyle** açılır; telefonda yavaşlatıyorsa varsayılan kapalı kalır.
- Öncelik grafiklerde; çok oyunculu eşitleme sonra.
- Test cihazı **Samsung Galaxy A34**; kalite ayarlarının varsayılanı buna göre seçilir.
- "Blok dokularına dokunma" kısıtı bu yol haritasıyla **kalktı** (G4 ve G5 için).

**Aşamalar**

| Aşama | İçerik | Dokunulacak yerler / notlar |
|---|---|---|
| G0 ✔ | FPS sayacı ve grafik kalitesi ayarı (düşük / orta / yüksek) | Ayar `Session` içinde saklanır (`user://settings.cfg`), duraklatma ya da ana menüden değiştirilir. Sonraki aşamalar bu ayara bakar. Telefonda FPS bilinmiyor; ölçüm buradan başlar. |
| G1 ✔ | Köşe gölgesi (ambient occlusion) | `ChunkMesher`: köşe başına AO, mesh renklerine işlenir (GL Compatibility'de SSAO yok). Şu an yüz parlaklıkları `sh := [0.8, 0.8, 1.0, 0.5, 0.65, 0.65]`. Mesher yalnızca 4 yan komşuyu alıyor; chunk köşeleri için çapraz komşular da gerekir. Dörtgenin köşegeni AO'ya göre çevrilmeli. |
| G2 ✔ | Gündüz-gece ve atmosfer | `game.gd` `_update_sky`: güneş şu an sabit açıda, yalnızca parlaklığı değişiyor. Güneş hareket etmeli; gün doğumu/batımı renkleri, sis rengi, gecenin fazla karanlık olması burada düzelir. Saat cihaz saatinden türetilir (tüm oyuncularda aynı), bu korunmalı. |
| G3 | Güneş gölgeleri | `DirectionalLight3D` gölgesi, yalnızca "yüksek" ayarda. Çözünürlük ve mesafe mobil için sınırlanır. Blok malzemesi hem güneşten ışık alıyor hem sabit yüz parlaklığı kullanıyor; gölge açıkken ikisi üst üste biner, yüz parlaklıkları yeniden dengelenmeli. |
| G4 | Blok dokuları (16 px) | `Atlas._pixel`: çim (doğal tonlar), toprak (küçük taşlar), taş (yüzey varyasyonu), kütük (kabuk ve halkalar), yaprak (dolgun), cevherler (belirgin mineral). |
| G5 | Doku varyasyonları | Atlas 8×8 = 64 hücre, 21'i dolu; varyasyonlara yer var. `ChunkMesher` konumdan türetilen sabit bir karma ile varyant seçer (tüm oyuncularda aynı görünmeli). |
| G6 | Kırma parçacıkları | Blok kırılırken kırıntılar (bloğun dokusundan renk), cevher kırılınca parıltı. Uzakta azaltılır / kapatılır. |
| G7 | Meşale ateşi | Alev animasyonu ve ışık titremesi. Meşale ışıkları `world.gd` içinde (satır 179 civarı `light_color`). |
| G8 | Yaprak ve çim sallanması | Yapraklar için köşe animasyonu (blok malzemesi `StandardMaterial3D`; shader gerekebilir) ve yeni uzun çim bitkisi bloğu. Yalnızca yakın chunk'larda. Yeni blok kimliği Firebase kurallarındaki sınırın (`<= 63`) içinde kalmalı. |
| G9 | Mob animasyonları | Baş, kuyruk, saldırı ve ölüm hareketleri (`scripts/mobs/mob.gd`). |

**Dikkat edilecekler**
- Performans ölçümü yalnızca telefonda anlamlıdır; PC'deki testler görünümü doğrular, hızı değil.
- Atlas ve mesh üretimi başlangıçta ve chunk yüklenirken çalışır; G1 ve G5 mesh kurma süresini artırır, chunk yükleme takılmasına bakılmalı.
- Düşük ayarda G3, G6, G8 kapalı olmalı; orta ve yüksek ayarın neyi açacağı G0'da belirlenir.

## Kalan işler

0. **Grafik yol haritası G0–G9** (yukarıda; sıradaki iş).
1. **Aşama 11 — çok oyunculu eşitleme** (grafiklerden sonra): moblar, hasar, sandıklar. Firebase kurallarına yeni alanlar gerekecek. Bu PC'de test edilemez; iki telefonla kullanıcı dener.
2. **Aşama 12 — dükkan:** kakacoin ile alış/satış, çok çeşitli yeni eşyalar (kullanıcı "ileride" dedi).
3. **Kullanıcının yapması gereken:** `firebase/database.rules.json` dosyasını Firebase Console'da yeniden yayınlamak (blok değeri sınırı `<= 63`; yayındaki sürümde hâlâ `<= 10`).

## Bilinen eksikler

- Takılı zırh/kalkan ve elde tutulan eşya 3. şahıs modelinde görünmez.
- Fırın yalnızca ekranı açıkken çalışır; su akmaz; mağara yok.
- Düşen eşyalar, envanter, moblar ve sandıklar çok oyunculuda eşitlenmez; katılan oyuncunun envanteri kaydedilmez.
- Kılıç, sandık, kase, yay gibi tarifler dışındaki Minecraft tarifleri yok.

## Dokunulmaması istenenler

- **Blok dokuları:** grafik yol haritası (G4, G5) kapsamında değiştirilebilir; çözünürlük 16 pikselde kalır.
- Tablodaki sayılar (can, hasar, XP, dayanıklılık) kullanıcıya sorulmadan değiştirilmez; denge ayarı kullanıcı telefonda denedikten sonra yapılır.
