class_name MobDB
## Mob tablosu (mns2026). Alanlar:
##   n: ad    k: sınıf (passive / semi / active / boss)    hp, atk, xp
##   size: (genişlik, yükseklik) çarpışma kutusu          speed: yürüme hızı (blok/sn)
##   hover: yerden yükseklik (uçan görünümlü moblar)

## Aktif mobların oyuncuyu fark ettiği yarıçap (blok).
const AGGRO_RADIUS := 10.0
## Takip mesafesi: bu kadar uzaklaşan oyuncunun peşi bırakılır. Aktif moblar daha uzağa kovalar.
const LEASH := {"semi": 16.0, "active": 28.0, "boss": 16.0}
## İki saldırı arası bekleme (sn) ve saldırı menzili (mob kenarından).
const ATTACK_INTERVAL := 1.2
const ATTACK_RANGE := 0.95

const DEFS := {
	"chicken": {"n": "Tavuk", "k": "passive", "hp": 15, "atk": 2, "xp": 2, "size": Vector2(0.5, 0.75), "speed": 1.6},
	"pig": {"n": "Domuz", "k": "passive", "hp": 20, "atk": 3, "xp": 2, "size": Vector2(0.8, 0.9), "speed": 1.5},
	"cow": {"n": "İnek", "k": "passive", "hp": 20, "atk": 3, "xp": 2, "size": Vector2(0.9, 1.3), "speed": 1.4},
	"sheep": {"n": "Koyun", "k": "passive", "hp": 20, "atk": 3, "xp": 2, "size": Vector2(0.8, 1.1), "speed": 1.5},
	"wolf": {"n": "Kurt", "k": "semi", "hp": 60, "atk": 7, "xp": 5, "size": Vector2(0.6, 0.85), "speed": 3.6},
	"bee": {"n": "Arı", "k": "semi", "hp": 60, "atk": 8, "xp": 5, "size": Vector2(0.5, 0.5), "speed": 3.4, "hover": 0.9},
	"angry_villager": {"n": "Kızgın Köylü", "k": "semi", "hp": 70, "atk": 10, "xp": 8, "size": Vector2(0.6, 1.8), "speed": 3.2},
	"wizard_villager": {"n": "Büyücü Köylü", "k": "semi", "hp": 75, "atk": 12, "xp": 10, "size": Vector2(0.6, 1.8), "speed": 3.2},
	"zombie": {"n": "Zombi", "k": "active", "hp": 100, "atk": 15, "xp": 15, "size": Vector2(0.6, 1.8), "speed": 3.0},
	"skeleton": {"n": "İskelet", "k": "active", "hp": 110, "atk": 15, "xp": 16, "size": Vector2(0.6, 1.8), "speed": 3.2},
	"creeper": {"n": "Creeper", "k": "active", "hp": 130, "atk": 20, "xp": 18, "size": Vector2(0.6, 1.6), "speed": 2.8},
	"golem": {"n": "Golem", "k": "boss", "hp": 1000, "atk": 50, "xp": 200, "size": Vector2(1.4, 2.7), "speed": 2.6},
	"giant_spider": {"n": "Dev Örümcek", "k": "boss", "hp": 800, "atk": 40, "xp": 150, "size": Vector2(2.0, 1.2), "speed": 3.4},
}
