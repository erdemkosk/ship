# Karanlık Deniz

Godot 4.6 ile yapılmış, ayarlanabilir hava durumlu, sandal sürülebilen gerçekçi 3D deniz sahnesi.

## Çalıştırma

Godot ile `project.godot` dosyasını açıp F5'e bas, ya da terminalden:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## Kontroller

| Tuş | İşlev |
|---|---|
| W / S | Motor ileri / geri |
| A / D | Dümen (sola / sağa dön) |
| Sağ fare (basılı tut) | Kamera döndür / bak |
| Fare tekerleği | Zoom (serbest modda hız) |
| F | Kamera modu: takip → FPS (teknede otur) → serbest |
| Fare | FPS modunda bakış doğrudan fareyi izler (ESC: çık) |
| Q / E | Serbest kamerada alçal / yüksel (Shift: hızlı) |
| Tab | Ayar panelini gizle/göster |

## Sağ panel ayarları

- **Rüzgar Hızı / Yönü** — dalga boyu, yönü ve bulut akışı rüzgardan türetilir
- **Dalga Yüksekliği / Dikliği** — Gerstner dalga genliği ve sertliği
- **Saat** — güneş konumu, gün/gece döngüsü (6 gün doğumu, 18 gün batımı)
- **Sis, Bulut, Yağmur, Fırtına (şimşek)** — atmosfer; bulutlar prosedürel
  gökyüzü shader'ında rüzgarla sürüklenir, gece açık havada yıldızlar çıkar,
  şimşek bulutları içeriden aydınlatır

Hazır ön ayarlar: Sakin Gece, Açık Gün, Açık Ufuk, Puslu Akşam, Fırtına, Kâbus.

## Gemi

9 metrelik, iki katlı eski bir ahşap tekne — ve içine girilebiliyor.

- **Alt kat**: kamer — ranza, masa, soba, yanan bir lamba. Baş ve kıç güverteye
  birer kapı, yani baş güverte → kamara → kıç güverte → merdiven → çatı →
  dümen evi diye yürünebilir bir tur var.
- **Üst kat**: dümen evi — dört yanı cam, dümen, harita masası, seyir lambası.
- **Gerçek cam** (`shaders/glass.gdshader`): temiz cam ışığın ~%92'sini
  olduğu gibi geçirir, o yüzden pane düşük alfalı düz geometri — ekran dokusu
  numarası yok, kırılma ofseti yok, görüntüyü bulandırabilecek hiçbir şey yok.
  Camlığını satan geriye kalan azlık: sıyırma açısında sert Fresnel parlaması,
  sıkı bir spekülerlik ve köşelere doğru kalınlaşan tuz filmi. Saydam yüzeyler
  origin'e göre sıralandığından cama `render_priority` verildi ki deniz her
  zaman camdan önce çizilsin.
- **Kapılar bir insan boyunda**: kapı lentosu 0.42'den 0.20'ye inip kamara
  tavanı yükseltildi — açıklık 1.55 m'den **1.92 m**'ye çıktı. Eskiden 1.74 m
  boyundaki adam kapıdan değil, kapının kirişinden geçiyordu.
- **Kamara döşeli**: lombozlu ranza (battaniye, yastık, deniz yatağı tahtası),
  fiddle raylı masa ve tabure, üstünde fiddle'lı kitap rafı, kapı yanında
  dolap, gemici sandığı, halı, ve kıç köşede kapağı köz gibi ışıyan soba —
  borusu güverte tavanından geçip çatıdaki bacaya bağlanıyor. Baca bu yüzden
  sancak kıç köşede: merkezde dursaydı merdiveni ve kapıyı kapatırdı, gerçek
  bir tesisatçı onu oraya asla koymazdı.
- **Aletler analog**: pirinç çerçeve, siyah kadran, krem iğne, 240°'lik yay.
  Parakete, iskandil ve zincir birer ibreli saat; pusula ise **kerteriz kartlı**
  — kart yeryüzüyle kalır, gemi altında döner, rota sabit ibre çizgisinin
  altında okunur. İğneler yerine oturmaz, salınarak gelir. Rakamlar kadranın
  üstüne kazınmış; ekranda dönen sayı yok.
- **Dümen evi**: gerçek bir kumanda mahalli gibi — kıç kapıdan dümene yürüyüş
  bomboş. Ön camın hemen altında tam genişlik **gösterge paneli** (pusula,
  iskandil, parakete, güç, zincir — `Label3D`, bakış hizasında), dümenin
  önünde bronz kubbeli **pusula dolabı** (binnacle), sancağında panele monte **gaz kolu**. Harita masası iskele duvarına katlandı.
- **E ile etkileşim**: baktığın şeyin adı ekranın altında belirir, E tutar,
  E bırakır. Dümen (tam kumanda), telgraf (yalnız güç kolu), baştaki ırgat
  (çapa), ışık panosu (ana şalter). Liste `boat.gd`'deki `INTERACT` sabitinde.
- **Güç göstergesi** gaz kolunun hemen arkasında, panelin sağ ucunda dikey şerit: sıfır
  çizgisinden yukarı **yeşil** (ileri), aşağı **kırmızı** (tornistan) dolar.
  Bir bakışta pervanenin hangi yöne, ne kadar döndüğü belli.
- **Gaz bir ayar, pedal değil**: W/S dümendeyken kolu ileri/geri
  yürütür, tekne kolu bıraktığın güçte seyre devam eder — sen güvertede
  gezerken, demir atarken de. Kol görsel olarak da hareket eder; sıfır
  civarında mandal var, dürtülen kol hayalet yol vermez.
- **Dümen ağır**: tork 155k'dan **52k**'ya indi, savrulma sönümü 30k'dan
  **86k**'ya çıktı ve dümen bir kanat gibi **üzerinden akan suyla** çalışıyor —
  otorite akışın karesiyle artıyor, yani yavaşken neredeyse hiç dinlemiyor.
  Dokuz metre ve dört buçuk ton fırlamaz: dümeni kırar, beklersin.

### Performans: Retina tuzağı

macOS'ta Godot varsayılan olarak pencereyi Retina fiziksel çözünürlüğünde
render eder. Tam ekranda bu, pencereli görünümün ~4 katı piksel demekti —
"pencerede 120, tam ekranda 50 FPS" farkının tamamı buydu.
`display/window/dpi/allow_hidpi=false` ile mantıksal çözünürlükte render
ediliyor; karanlık bir sahnede 2x ölçekleme görünmez, kare bütçesi görünür.
Aynı 1440p ölçümü: 66 → 120 FPS (vsync tavanı).
- **Direk başında kırmızı ikaz feneri**: iki kısa çakış, sonra uzun karanlık.
  Kıçtaki fener kaldırıldı; içerisi zaten yeterli.
- **Işık anahtarları** dümenin başında: `1` kamara, `2` dümen evi, `3` ikaz
  feneri, `6` ileri projektörler. Panodaki `E` ana şalter. Dört devre, dört
  şalter — pano da dört mandala indi.
- **İki ileri projektör**: iki katın arasında, çatının baş kenarında, dışarıda;
  pruvanın önünü aydınlatıyorlar. Kendi devreleri — `6`.
- **Güverte lambaları tamamen kaldırıldı** — önce kamara kapılarındaki ikisi,
  sonra dümen evi kapısındaki sonuncusu. Devresi (`4`), anahtarı, malzemesi ve
  ışıkları da kodla birlikte gitti. Kamara, dümen evi ve projektörler gemiyi
  zaten aydınlatıyor; güverte hattı bu lambalarla kalabalık duruyordu.
- **Yağmur camları yıkar**: cam shader'ı yağmur şiddetiyle aşağı süzülen su
  sütunları çizer. Ön camda `5` ile çalışan **silecek** var — fiziksel kol
  camın dışında süpürür, süpürdüğü yelpaze şader tarafında kuru kalır.
- **Kapalı alanlara yağmur girmez**: güverte ve çatılar `GPUParticlesCollisionBox3D`
  taşır, yağmur damlaları değdiği yerde ölür (`HIDE_ON_CONTACT`) — kamaraya,
  dümen evine damla düşmez, güvertenin içinden de geçmez.

### Güvertede yürümek

FPS modunda (`F`) gemide serbestçe yürünüyor. Bu, oyuncunun **teknenin kendi
koordinat sisteminde** simüle edilmesiyle çalışır (`scripts/deck_walker.gd`):

- Beş metre savrulan, yirmi derece yatan bir rigid body'nin üstünde
  CharacterBody3D yürütmek fizik motoruyla kavga etmektir — kayar, güverteden
  geçer, tekne hızlanınca geride kalır. Oyuncu bunun yerine konumunu teknenin
  koordinatlarında tutuyor ve dünya uzayında hiç hareket etmiyor; tekne onu
  taşıyor, tıpkı bir güvertenin seni taşıdığı gibi.
- **Yerçekimi** dünya uzayında kalmak zorunda, o yüzden her karede yerel çerçeveye
  döndürülüyor. Gemi yattığında alabora yakasına doğru kaymanın ve fırtınada baş
  güvertede durmanın iş olmasının sebebi o tek satır.
- Çarpışma da fizik motoru değil: geminin yürünebilir hacmi `boat.gd`'nin
  yayımladığı kısa bir eksen hizalı dikdörtgen listesi, silindiri ona çözmek on
  küsur satır ve asla tünellemiyor.
- `E` dümeni tutar/bırakır. Dümendeyken WASD tekneyi sürüyor, bıraktığında
  ayaklarını.
- **Denize düşersen yüzersin**: küpeşteyi aşan oyuncu dalga yüzeyinde,
  akıntıyla sürüklenerek yüzer. Suya girdiği an kendine ait bir **dünya
  konumu** alır: eskiden konum teknenin çerçevesinde tutulduğu için gövde
  uzaklaşırken koordinatlarını da sürüklüyor, adam tekneyle aynı hızda
  gidiyordu.
  Gövdeye yanaşınca `SPACE` küpeşteden güverteye çeker. Eskiden düşen oyuncu
  teknenin yerel çerçevesinde sonsuz düşüşte, yalpayla ileri geri seğiriyordu.
- **Dik merdiven kalktı, yerine iç merdiven geldi.** Dışarıdaki dik merdiven
  ne yapılırsa yapılsın sorun çıkarıyordu: yakalama hacmi kapıyı kapatıyor,
  hacimden çıkarken düşürüyor, moda girip çıkmak sinir bozuyordu. Şimdi kamaranın
  iskele tarafından çıkan **sekiz basamaklı bir kamara merdiveni** var, güverte
  tavanındaki bir açıklıktan dümen evine ulaşıyor.
  Kritik nokta: basamaklar **modu olmayan sıradan zeminler**. Her rıht 0.28 m,
  yürüyüşün adım yüksekliği (0.42) bunun üstünde olduğu için normal yürüyerek
  çıkıp iniyorsun — tutunma yok, mod yok, takılacak bir şey yok.
- **Merdiven 0.94 m açıklığında.** İlk hali 0.66 idi: gövde yanağı seni içeri
  ittikten sonra geriye 0.03 m kalıyordu, yani omuz omuza sürtünen bir yarık.
  Asıl suçlu genişlik değildi ama — **dümen evinin kıç kapı pervazı merdiven
  boşluğunun tam üstünde duruyordu**, ve ayakların basamaktayken kafan üst
  kattaydı, dolayısıyla o pervaza çarpıyordun. Üç şey değişti:
  1. Dümen evi 0.96'dan **1.10 yarı-en**'e genişledi; kazanılan 14 cm doğrudan
     merdiven başına gitti.
  2. **Kıç kapı iskeleye alındı**, merdivenle aynı hizaya. Artık basamakları
     çıkıp doğrudan kapıdan giriyorsun; dönülecek direk yok.
  3. Dümen evi kıça uzatıldı (`WH_Z1` 2.15 → 2.70) ki merdiven boşluğunun
     tamamı **çatı altında ve kuru** kalsın. Baca da buna göre dirsek yapıp
     kıçtan çıkıyor.
  Merdiven ayrıca bir basamak öne kaydırıldı: dibinde artık **sahanlık** var,
  eskiden son basamak kamaranın arka perdesine dayanıyordu ve inince yana
  kaymadan kamaraya adım atamıyordun.
- **İki kapı eşiğinde zemin deliği vardı** — kamara tabanı z 3.08'de bitiyor,
  kıç güverte 3.20'de başlıyordu. Tam kapının altındaki bu 12 cm'lik boşluk
  kapıdan çıkarken seni düşürüyordu. İki eşik de kapatıldı.
- Doğrulama offline: yürüyüşün `_resolve_floor` / `_resolve_walls` /
  `_resolve_ceilings` mantığı birebir simüle edildi. Merdiven **beş ayrı
  yanal hatta, iki yönde de** yürünüyor; basamak başına serbest yanal alan
  0.63–1.44 m; sekiz basamağın hiçbirinde tavan sıkışması yok; ve baştan
  kıça bütün güverte turu hiçbir noktada düşmüyor.
- **Merdiven ağzında gerçek küpeşte.** Görsel bir eşik vardı ama çarpışma
  hacmi yoktu, dolayısıyla dümen evinde yan yürürken boşluğa adım atıp
  düşüyordun. Şimdi iç tarafta ve kıç ucunda katı bir küpeşte var; baş ucu
  açık, yani deliğe girmenin tek yolu merdiveni inmek.
  İnce nokta: küpeştenin tabanı güverte hizasında (2.91) değil **3.05**'te.
  O 14 santim tasarımın kendisi — güvertede duranın (ayak 2.91, baş 4.65)
  önünü kesiyor, ama alt basamaklardakinin başı (2.70 ve 2.98) altından
  geçiyor. Tabanı güverte hizasına koyunca küpeşte merdivendeki adamın
  kafasını yakalayıp inmesine izin vermiyordu.
- **Çatının kıç kenarı boydan boya korkuluklu** — artık aşağı inmenin yolu
  dümen evinden merdivene, oradan kamaraya. Arkadan düşecek yer kalmadı.
- Merdivenin korkulukları gerçek gemi merdiveni gibi çatının üstüne uzanır ve
  yakalama hacmi çatı hizasını aşar — çatıdan geri adım atınca merdivene
  binersin, kıç küpeştesinin üstünden denize uçmazsın. Merdivendeyken eller
  küpeştede: yanlara savrulmazsın.

### Çapa

`G` ya da baş güvertedeki ırgatın başında `E` — funda/vira. `scripts/ground_tackle.gd`:

- Çapa **taş gibi batar** (suda ~7 m/s terminal); zincir yalnızca çapanın
  düşüşüyle açılır — kaçan tekne zinciri açamaz, zincir gerilir ve tekneyi
  çeker. Sarkan çapa yatayda süpürülür ama derinliği kutsaldır, yoksa seyir
  hâlindeki teknenin altında dibe hiç varamazdı.
- Dibe oturduğu an hedef zincir **kilitlenir** (mesafenin %112'si + 2 m):
  tekne birkaç metre salınır ama attığın yerde kalır, 70 metrelik zincir
  sahasında dolaşmaz.
- **Tutma gücü** motorun verebileceğinin çok üstünde: demirdeyken tam yol
  bassan bile zincir yarıçapından çıkamazsın — çapa etrafında savrulursun,
  gerçekte de öyle olur. Vira edince kurtulursun.
- Kuvvet **loça mevkiinden** (baştan) uygulanır — demirli teknenin rüzgâra baş
  vermesinin sebebi. Katener çizimi: boşta karın, gergin düz hat.

### Harita masası

Dümen evinin sancak kıç köşesinde, kâğıt haritalı bir masa. `E` ile üstüne
eğiliyorsun — kamera 0.45 saniyede masaya iniyor ve haritaya yerleşiyor, sonra
fare yeniden senin oluyor, yani başını kaldırıp camdan bakmak için masadan
kalkman gerekmiyor. Ekran arayüzü yok; harita odadaki bir nesne, okumak da
vücudunla yaptığın bir şey.

**Haritadaki kıyı, sudaki kıyı.** `chart.gdshader` deniz dibinin *aynı* RF
yükseklik dokusunu okuyor — deniz tabanı meshi ve kıyı köpüğü hangi dokuyu
okuyorsa o. Yani kâğıttaki her burun, her on metre eğrisi gerçekten dışarıda
olan. Elle çizilmiş bir harita olsaydı arazi her değiştiğinde dünyayla arası
açılırdı; bu açılamıyor.

Üstünde bir haritada ne varsa o var: derinlik eğrileri, sığlıklara vurulmuş
boya, iskandil noktaları, koordinat ağı, pusula gülü, ve bir süredir gemide
olduğunu belli edecek kadar leke ve kahve halkası. Dümen evi lambasıyla
aydınlanıyor, çünkü bir şeyi gerçek yapan şeyin yarısı odadaki ışığın onun
üstüne düşmesi.

Nerede olduğunu **pirinç bir iğne** gösteriyor: dünya koordinatın 0..1'e
katlanıyor, ki dünya zaten öyle sarılıyor — projeksiyon yok, kayacak ölçek
yok. Altında kurşun kalemle çizilmiş mevkiin ve rotan var.

### İskandil ve telsiz

Dümenin sancağında, cam kenarına vidalanmış bir **derinlik iskandili**. Gemideki
tek elektronik ve öyle de görünüyor: tek renkli fosfor panel, gemi tesisatından
besleniyor, yani kötü besleniyor — ekran nefes alıp veriyor, arada bir tamamen
kırpışıyor.

İz **gerçek**. `boat.gd` son yarım dakikanın omurga altındaki gerçek deniz
dibini besliyor, dolayısıyla camda soldan sağa yürüyen şey az önce üstünden
geçtiğin zemin. Sığlığa dümen kırarsan, hissetmeden önce onun sana doğru
yükseldiğini görüyorsun. Yedi parçalı derinlik göstergesi de dahil her şey
shader'da çiziliyor — ne doku var ne viewport, çünkü yedi dikdörtgen ve bir
arama tablosu, ve böylece gösterdiği derinlikle asla arası açılmıyor.

Üstünde **radar** — PPI, yani yuvarlak olanı, üstünde çizgi dönen. O da uydurma
değil: her piksel için o noktanın hangi kerteriz ve mesafeye denk geldiğini
çözüyor, bunu dünya koordinatına çeviriyor ve deniz dibi yükseklik haritasına
"burada kara var mı" diye soruyor. Yani ekrandaki kıyı dışarıdaki kıyı; puslu
havada zar zor seçtiğin bir burun ekranda tam yerine düşüyor.

Baş-yukarı çalışıyor, küçük setlerin çalıştığı gibi: ekranın üstü geminin başı,
dolayısıyla sen döndükçe kara ekranda dönüyor. Süpürme kasten yavaş (7.5 dev/dk)
ve fosfor izi uzun — eski bir setin ele veren yanı bu; yenisinde fosfor sönmeden
tazeleme geldiği için resim öylece durur, bunda boyanın dönüşünü izliyorsun.

Yönü kontrollü doğrulandı: tekne başı kuzeye sabitlenip bilinen karayla
karşılaştırıldı — fener kayalığı sancak baş omuzlukta menzilin beşte birinde,
güney burnu kıçta yarısında. (İlk bakışta ters sanmıştım; düşük çözünürlükte
ekranın merkezini yanlış okumuşum.)

Yanında **telsiz**. `E` ile ahizeyi eline alıyorsun, ve aldığın yere **kordonla
bağlı kalıyor**: 48 küçük silindir her karede bir sarmal boyunca diziliyor,
sarmal sete yaklaştıkça sıkışıyor, uzaklaştıkça açılıyor. Kordonun boyu kordonun
boyu — fazla uzaklaşırsan ahize elinden çekiliyor ve sete geri dönüyor, sabit
bir VHF ahizesiyle güverteye çıkmaya kalkarsan olacak olan da tam bu.

### Elektrik, yaşlı bir teknenin elektriği

Bu tekne yeni değil ve olmamalı da. Tesisat eski, bağlantılar tuzlu, ve hava
sertleştikçe hiçbiri çalışmak istemiyor. `_supply` rüzgârdan, yağmurdan,
fırtınadan ve teknenin denize çakılmasından besleniyor; sertlik arttıkça:

- İskandil ve radar **karartıyor**, kırpışıyor, ve arada resmi tamamen
  kaybediyor.
- Ampuller de onlarla birlikte kısılıyor — hepsi aynı akü, ayrı ayrı
  davranmaları saçma olurdu.
- Ve düşük ihtimalle **tam kesinti**: 0.1–0.85 saniyelik karanlık, ihtimali
  sertliğin karesiyle artıyor. Sakin bir gecede neredeyse hiç olmuyor; kâbusta
  sık sık oluyor.

### Makine ve dümen gecikmeli

Gaz kolu artık bir **istek**, gaz pedalı değil. Şaftın ucunda pervane, arkasında
dört buçuk ton tekne var; anında cevap vermez. Üç ayrı zaman sabiti:

| geçiş | sabit |
|---|---|
| devir alma | 1.9 sn |
| gazdan çıkma | 1.5 sn |
| ileriden geriye | 3.6 sn |

Sonuncusu en uzunu çünkü makinenin durup ters yönde yeniden çalışması gerekiyor.
"Büyük" hissini veren şeyin çoğu bu gecikme — ve yavaş yola çok önceden
çalman gerektiğinin sebebi.

Konsoldaki güç çubukları **kolu değil şaftı** okuyor, yani makinenin telgrafı
kovalayışını izliyorsun. Dümen de öyle: `_helm` girdiyi 1.45 sn'lik bir sabitle
takip ediyor, alabanda iki-üç saniye kol çevirmek demek. Fiziksel dümen yelpazesi
ve dümen evindeki çark bu duruma bağlı, girdiye değil.

Dönüş bir kez daha ağırlaştı: tork 52k → **33k**, savrulma sönümü 86k → **124k**.

### Şaft göstergesi

Gaz kolunun yanında, pirinç çerçeve içinde **on üç segment**: durak işaretinin
altında dört kırmızı (tornistan), üstünde sekiz yeşil (ileri). Yanan segmentin
en üstteki'i daha parlak — gerçek bir bar gösterge de öyle yapar, ve gözün
oraya iniyor. Her dördüncüde uzun taksimat var, sayarak okumayasın diye.

Gösterge **kolu değil şaftı** okuyor. Yanındaki küçük bronz iğne ise kolun
kendisi, yani **iki işaret arasındaki fark gecikmenin ta kendisi** — gaz verince
iğne fırlıyor, segmentler arkasından geliyor. Eskiden bu iki tane uzayıp kısalan
kutuydu; uzayan bir kutu boya çubuğu gibi okunuyor, alet gibi değil.

Elektrik düşünce bu da sönüyor, gemideki her şey gibi.

### Çapa

İki şey yanlıştı.

**Çapa suya dik inmiyordu.** Eski kod düşerken onu yanlamasına tekneye doğru
süpürüyordu — funda etmek funda etmek gibi görünmemesinin sebebi buydu, kahpe
suyun içinde peşinden kayıyordu. Artık bırakıldığı **xz'yi tutuyor**: baştan
atılan demir, atıldığı yere iniyor. Suya girerken de sıçratıyor.

Zincir bu sırada tamburdan **serbest** akıyor, hem düşüşe hem teknenin devam
eden yoluna yetişecek kadar. Serbest ırgat bunu yapar, ve demir atarken neden
ağır ağır tornistan verildiğinin sebebi de budur.

**Zincir yay değildi.** Asıl fark bu. Bir halat ya da zincir, boyunu geçince
daha çok gerdikçe daha çok itmez — **durdurur.** O yüzden artık teknenin
kablo boyunca dışa doğru olan hızı doğrudan alınıyor, kalan gerginlik sonra
kapatılıyor, ve hepsi **loça makarasından** uygulanıyor — bu yüzden yandan
sürüklenmek yerine burnu çapasına dönüyor.

Ölçüldü: 13.2 m/s ile giderken zincir gerildiğinde tekne **iki saniyede
0.7 m/s'ye** düşüyor. Eski yay modeli onu ipin ucunda zıplatıyordu; bir demir
donanımı asla zıplamaz.

**Ve artık görülüyor.** Üç ayrı sorun vardı:

- **Çapa istifteyken hiç çizilmiyordu.** Görünmemesinin sebebi buydu. Artık
  makaraya kastro edilmiş duruyor — omurluk baş-kıç yatık, tırnaklar bodoslamanın
  üstünde, yani bir çalışan teknede çapanın yaşadığı yerde.
- **Zincir 14 parçaydı.** Yetmiş metrelik kabloda bu, halka başına beş metrelik
  bir çubuk demek: tel gibi okunuyordu. Şimdi **96 parça**, ve her ikincisi
  diğer yöne yassıltılmış — gerçek halkalar birbirine dik geçtiği için ışığı
  dönüşümlü bantlar hâlinde tutar, ve silindir dizisini zincir gibi gösteren
  şey tam olarak budur. Rengi de siyah demirden **galvanize**ye çevrildi; eskisi
  hem gövdeye hem denize karışıp kayboluyordu.
- **Su altında hiç sönmüyordu.** Düz bir malzemede zincir yirmi metre derinde
  de güvertedeki kadar parlak kalıyordu, yani suyun *içinde* bir şey gibi değil,
  suyun *üstüne çizilmiş* bir şey gibi okunuyordu — batan çapayı yansımaya
  benzeten şey tam olarak buydu. Artık kendi shader'ı var ve derinlikle denizin
  rengine dönüşüyor, deniz dibi yosunuyla aynı sayılarla.
- **Ve aynasında hayaleti vardı.** Düzlemsel yansıma, düzlemin *altındaki* bir
  şeyi havada asılı bir hayalet olarak geri veriyor. Demir donanımı artık ayrı
  bir görüntü katmanında ve yansıma kamerası onu hiç görmüyor.
- **Zincirin asılışı yanlıştı.** Simetrik bir sinüs kamburuydu: göbek tam
  ortada, yani ağırlığı olan bir zincir gibi değil, asma köprü halatı gibi
  duruyordu. Şimdi teknenin yanında dik, dibe doğru yassı asılıyor — ve
  demirlediğinde fazlalığın çoğu **dibe seriliyor**, kabloyu çapadan yatay
  çıkarıp yalnızca tekneye yaklaşınca kaldırarak. Bir kaloma zinciri zaten
  bunun için vardır.
- **Irgat dönmüyordu.** Kabloyu salmak ve toplamak tek işi olan parça, sabit bir
  kutuydu. Şimdi **loçası dönüyor** — hızı doğrudan o an tamburdan çıkan metre
  cinsinden kablo, yarıçapına bölünmüş. Etrafına da diş kondu; pürüzsüz bir
  tambur dönerken duruyormuş gibi görünür.
- **Kablo gövdenin içinden çıkıyordu.** Loça makarası baş içine gömülüydü.
  Bodoslama başına, küpeştenin üstüne **gerçek bir makara** kondu — iki yanak,
  bir makara, bir de güvertede ırgatla makara arasına stoper. Kablo artık
  ırgattan güverte boyunca gelip makaradan aşıyor ve oradan suya iniyor.

### Adalar ve karaya oturma

Gemi adaların içinden geçiyordu. Sebebi şuydu: her adaya bir silindir çarpışma
gövdesi konuyordu, **ama yalnızca 14 metreden dar olanlara**. Yani ada adını hak
eden her şey ıskalanıyordu — ve dar olanlarda da görünmez bir varile çarpıyordun.

Silindirler kaldırıldı. Deniz dibi zaten bir **yükseklik haritası**, o yüzden
gemi doğrudan onu yokluyor: omurga hattında yedi nokta, her fizik adımında
zeminle karşılaştırılıyor (`boat.gd/_run_aground`). Değdiği noktadan yukarı
itiliyor — düz bir asansör gibi değil, baş omuzluk önce değdiği için başını
kaldırarak, yan bastığında yatarak.

Sürtünme **Coulomb**, viskoz değil. Bu önemli: hıza orantılı sürtünmenin her
zaman itmeyle dengelendiği bir hız vardır ve tekne sürünür — ilk sürüm onu
saniyede 30 santim kumsala tırmandırıyordu, ta ki deniz seviyesinin beş metre
üstünde, makinesi hâlâ dönerken oturana kadar. Kuru sürtünmenin böyle bir denge
noktası yok: sınırın altında hiç kıpırdamıyor. Ayrıca eğimden aşağı, derin suya
doğru bir itme var, yoksa tam gazda adaya tırmanmaya devam ederdi.

Ölçüldü: 11.6 m/s ile gelen tekne sığlıkta **2 saniyede** duruyor, ve tam
tornistanla **~6 saniyede** kurtuluyor. Temelli saplanmak kabul edilebilir bir
sonuç değil, hata olurdu.

**Kara az ve uzak.** Eskiden yalnızca fener kayalığı gerçek bir adaydı; geri
kalan her şey 2–7 metrelik kayaydı. Şimdi **iki büyük kara parçası** var (96 ve
124 m yarıçap, 19 ve 26 m yükseklik) ve **beş kayalık** — hepsi uzakta. Beş ada
denedim, ufuk takımadaya döndü; burası derin su, karanın bir *olay* olması
gerekiyor. Serpiştirilmiş küçük kayaların yoğunluğu da %48'den **%15**'e indi.

Ada damgası da yuvarlak olmaktan çıktı: iki sinüs terimi her adaya kendi
burunlarını ve koylarını veriyor. Kusursuz bir kara diski yakından bakınca
damga gibi duruyordu.

### Gemi büyüdü, merdiven merdiven oldu

Ölçtüm, göz kararı yapmadım. Eski hâlde:

- Merdiven **49.6°** — 0.279 rıht, 0.238 basamak. Bu merdiven değil, basamakları
  doldurulmuş bir iskele. Rahat inilmemesinin sebebi buydu.
- **Ranza ile soba 44 × 17 cm çakışıyordu** — soba ranzanın ayak ucunun içinde
  duruyordu. **Dolap da baş perdeye gömülüydü.**

Gemi **borda başına +0.30 m** açıldı ve **kıça +1.50 m** uzadı (gövde 8.3 → 9.8).
Kazanılan yerin çoğu merdivene gitti: **10 basamak, 0.223 rıht, 0.30 basamak
genişliği → 36.6°.** Ve boşluk 1.30 m: 0.60'lık bir gövde iki duvar arasında
0.70 m'lik serbestlik buluyor, yani basamakta dönebiliyorsun.

**Merdiven artık katı bir cisim.** Basamaklar zemindi, dolayısıyla altları
boştu: kamara tabanından merdivenin yan yüzünden içeri girip içinde duruyordun.
Her basamak için tabandan yukarı bir hacim var, ve tepesi **kendi basamağının
50 cm altında** bitiyor.

Elli, ve bu sayı önemli. Basamak genişliği 0.30, gövde yarıçapı da 0.30 — yani
sen daha *n+2*'nci basamaktayken omzun *n*'inci basamağın altına değiyor, iki
basamak ileriye, o yüksekliğe çıkmadan çok önce. Payı bir rıht (0.22) ya da bir
buçuk (0.30) bıraktığında o hacim seni tam bir sonraki basamağın dikdörtgeninin
sınırında geri itiyor: sınıra varıyorsun, zemin testi sınırı dışarıda bırakıyor,
ve merdivenin ortasında çakılıp kalıyorsun. **İki rıht** bıraktığında o hacim,
içine girmen gereken anda zaten yok sayılıyor ve çıkış akıyor.

En alttaki iki basamağın altı hiç kapatılmadı — giriş orası ve aynı hesap
kapıyı da duvara çevirirdi.

Doğrulama üç ayrı adım büyüklüğünde yapıldı (0.050 / 0.025 / 0.012 m), çünkü bu
bir sınır hatasıydı ve kaba adım onu atlayabiliyor. Simülasyon `Rect2.has_point`
gibi **yarı açık** aralık kullanacak şekilde düzeltildi; sorunu açığa çıkaran da
o oldu.

Kapılar **kapalı başlıyor**; gemiyi kendin açıyorsun.

Küpeşte de **1.55'ten başlıyor**, boşluğun ta baş ucundan değil. İlk iki basamak
güverte hizasında ve **giriş** onlar; korkuluk boydan boya geçince dümenden kıça
yürüyünce ona toslayıp yeniden ta öne dönmen gerekiyordu. Gerçek bir merdiven
korkuluğunda geçiş için boşluk vardır, artık bunda da var.

Kamara üç bölgeye ayrıldı ve hiçbir hacim bir diğerine girmiyor: **baş koy**
(masa ve tabure iskelede, dolap ve sandık sancakta), **koridor** (merdiven
iskelede, ranza sancakta, aralarında 1.49 m boş güverte), **kıç koy** (soba, ve
merdivenin dibi). Soba kıça geçtiği için baca da dümen evinin arkasından dosdoğru
çıkıyor — dirseğe gerek kalmadı.

Baş güverte temizlendi: ortasındaki ambar kapağı ve yanındaki sandık kaldırıldı.
Dışarıda iş gören tek şeyler ırgat ve direk.

### Kumanda konsolu ve kapılar

Dümen evi artık **tek bir konsol**. Ön pano, şalter tablosu ve harita masası
üç ayrı mobilyaydı, yan yana duruyorlardı; şimdi sancak boyunca panonun
köşesinden harita masasının ucuna kadar giden **tek bir marangozluk** var —
ortak gövde, ortak tabla, iç yüzünde çekmeceler. Şalter tablosu o tablanın içine
gömülü bir arduvaz levha, harita da onun kıç ucunda bir mazgalın içinde.

Altı pirinç anahtar: kamara, dümen evi, ikaz, projektör, **silecek** ve **çapa**.
Her biri klavyedeki kısayolun açtığı devrenin ta kendisi — tuşlar bu anahtarların
kısayolu, ayrı bir sistem değil. Yüz **düz**: eğik olunca anahtarlar tavana
bakıyor ve yazılar durabildiğin hiçbir yerden okunmuyordu.

Her anahtarın yanında **kırmızı/yeşil bir lamba**. Yananı dümenden bir bakışta
okuyorsun, ve elektrik düşünce onlar da sönüyor.

**Dalgada nişan almak.** Gemi ayağının altında yalpalıyor, dolayısıyla
nişanladığın şey iki dalga arasında nişanın altından kayıyor — ve anahtarlar
10 cm'lik hedefler. İki düzeltme, ikisi de soruna sebep olan şeye bağlı: her
hedef geminin **o anki açısal hızıyla orantılı olarak büyüyor** (sakinken
hassas, sertken affedici), ve **hâlihazırda teklif edilen** şey ayrıca 1.75×
bonus alıyor, yani bir kez bulduktan sonra yalpalar arasında kaybolmuyor.

**Nişan alma değişti.** Eskiden yalnızca hizaya bakıyordu, yani arkadaki büyük
bir hedef öndeki küçüğün nişanını çalabiliyordu — anahtarın tam üstüne bakıp
harita masası teklif edilebiliyordu. Artık her parça için ışın-küre testi var ve
en yakın isabet kazanıyor; `r` sadece "bu şey ne kadar büyük bir hedef"
demek. Anahtarların yarıçapı 10 cm ve aralarında 20 cm var, yani her birine tek
tek, rahatça basılıyor.

Kapılar da artık gerçek: menteşesinde dönüyor, `E` ile açılıp kapanıyor, ve
**kapalıyken kapı ağzına bir engel koyuyor** — yani içinden geçemiyorsun.
`BLOCKERS` sabit olmak zorunda (yürüyüş onu her karede okuyor), o yüzden hareket
eden ikisi ayrı bir listede duruyor ve `deck_walker` ikisini de çözüyor.

### Gemi genişledi

Merdiven kamaranın iskele boyunu baştan sona kaplıyor. Geriye kalan sancak
koridoru 1.15 m'ydi ve içine 0.78 m'lik ranza konunca **0.08 m** kalıyordu —
yani yatakla merdiven arasından geçmek matematiksel olarak mümkün değildi;
ileri yürümek istediğinde seni merdivene çıkarıyordu. Mobilyayı oynatmak
çözmüyor: bu kamara, merdiven yarısını aldıktan sonra fiziksel olarak küçük.

Bu yüzden **borda başına +0.34 m** açıldı (en 2.88 → 3.56). Gövde kaplaması,
küpeşte, güverte, kamara, dümen evi, korkuluklar, projektörler, baca, su
kesme probları ve çarpışma gövdesi hep birlikte büyüdü; yalpa ataleti de ene
göre yeniden hesaplandı (9000 → 13800), yoksa geniş bir tekne dar bir teknenin
yalpasıyla sallanırdı.

Ranza da 0.78 → 0.68 m'ye indi ve sancak perdesine dayandı. Merdiven ağzı ile
ranza arasındaki geçit artık **0.85 m serbest** — beş ayrı hatta yürüyerek
sınandı, hiçbirinde takılma yok.

### Yağmur

- **Damla sayısı 420 → 3600**, ve 56 × 56 m'lik kutu 24 × 24'e daraldı. Otuz
  metre ötedeki damla hiçbir iş yapmıyordu; etki tamamen *durduğun yerdeki*
  yoğunluk.
- **Ömür 0.36 → 0.85 sn.** Eskisi yedi metre düşüyordu, on bir metre yukarıdan
  bırakılınca kameranın dört metre üstünde ölüyordu — yağmur gökyüzünde asla
  içine giremediğin bir banttı. Artık yanından geçip denize iniyor.
- **Sürgü doğrusal değil** (`pow(rain, 0.55)`): yağmur %100'de %50'nin iki katı
  hissettirmez, biraz daha fazla hissettirir. Orta ayar zaten dışarı
  çıkılmayacak bir hava gibi görünsün diye öne yüklendi.
- **Gövde yağmurda ıslanıyor** — `soak` artık baş dalgasının yanı sıra yağmuru
  da dinliyor, yarım saat yağdı mı bütün kaplama koyulaşıyor.
- **Kapalı yerler kuru kalıyor** — ama bunun için kalkanların **kalın** olması
  gerekiyordu. Damla saniyede 20 metreden hızlı düşüyor ve sistem sabit adımla
  ilerliyor; iki test arasında neredeyse bir metre yol alıyor, dolayısıyla
  24 cm'lik bir çarpışma levhası çoğu karede orada bile değil. Yağmurun çatıdan
  girmesinin sebebi buydu. Artık her hacim **altındaki odanın tamamını
  dolduruyor** — içeri giren damla, adım nereye düşerse düşsün anında ölüyor.
  Ayrıca damlaya gerçek bir yarıçap verildi (varsayılan 1 cm; yarıçapsız damla
  hiçbir şeye çarpamaz) ve simülasyon 30 → 60 Hz'e çıktı.

### Cam ve silecek

Cam üç ayrı ölçekte ıslanıyor, çünkü camdaki su aynı anda üç şeydir: aşağı
sürünen **geniş perdeler**, onların içinde daha hızlı akan **ince dereler**, ve
bir şey sarsana kadar asılı duran **iri damlalar**.

Damlalar **gerçek damla**, gürültü lekesi değil: kaydırılmış bir ızgarada her
hücreye bir damla düşüyor, yarıçapı rastgele, kenarı keskin. İki nüfus var —
her yere serpilmiş küçükler ve daha seyrek iri olanlar — ve yoğunlukları
yağmurla artıyor. Yanlarında akmış ince dereler ve geniş perdeler.

Her şey **panele sabit**. Önce dünya koordinatına bağlıydı, yani gemi yol
aldıkça bütün desen camın üstünden kayıyordu: yerinde duran su, altından çıkıp
giden tekne. Cam üstündeki suyun asla yapmadığı tek şey bu.

**Silecek kademeli temizliyor.** Süpürgenin fazı shader'a veriliyor; shader da
kolun herhangi bir noktadan *ne kadar önce* geçtiğini çözüyor (kol
`1.02·sin(faz)`, yani her noktayı devirde iki kez kesiyor — hangisi daha
yakınsa o). Bıçağın hemen arkası temiz, ve su bir-iki saniyede geri doluyor.
Yağmur sertleştikçe daha hızlı doluyor — gerçek bir sağanakta silecek karşı
kıyıya varmadan tartışmayı kaybediyor. Kolun önünde ittiği bir su dalgası da
var, ve silinmiş cam hiç kurumuyor: bulaşık bir film kalıyor.

**Yansıma kasten çok düşük tutuldu.** Düzgün yansıtan bir cam denizi de
yansıtır, ve deniz hiç durmaz: dümende dururken gerçek okyanusun önünde ikinci,
yüzen, ters bir okyanus kayıyordu. Fiziksel olarak doğru, ve gerçekten mide
bulandırıcı. O yüzden Fresnel alfaya ancak değiyor, spekülar camın gerçek
değerinin küçük bir kesri, ve yüzey yakaladığı azı da resim değil yumuşak bir
parıltı olarak verecek kadar pürüzlü bırakıldı. Normal bozulması da aynı
sebeple neredeyse sıfıra çekildi — açıkken gemideki her lambayı akan suyun
üstüne yayıyordu, dört saniye muhteşem duruyor sonra dümen evinde durulmuyordu.

Cam rengi de koyulaştırıldı: pano lambası cama vurup denizin önüne sıcak bir
tül asıyordu. Dışarı baktığın bir pencere arkandaki odayı zar zor görmeli.

Ve yağmur kesilince cam **anında kurumuyor**: saniyede 0.055 ile siliniyor,
yani tam ıslaktan kuruya ~18 saniye. Silecek de tam bu yüzden var.

- **Göz yüksekliği yumuşatılıyor** — ama teknenin kendi ekseninde, dünya
  ekseninde değil. Merdiven ayağı 0.28 m'lik sıçramalarla kaldırıyor; göz
  doğrudan ayağa bağlıysa merdiven bir dizi kesme (jump cut) olarak çıkıyor.
  Dünya ekseninde yumuşatsaydım teknenin kendi savrulmasını da yumuşatmış
  olurdum ve ufuk yaylanırdı — o yüzden yalnızca yerel yükseklik.
  1.10 m'den büyük atlamalar (dümene geçmek, denizden çıkmak) anında geçiliyor.
- **Adım salınımı** — hız ve yerde olma durumuna bağlı, 2.2 cm. Var olduğunu
  fark etmiyorsun, olmadığında yürüyüş ölü hissettiriyor.
- **Güverte yalpası görüşe yansıyor** — ama üçte biri, ±7.5° ile sınırlı.
  Tam yalpa mide bulandırıyor, dümdüz ufuk ise fotoğrafın üstünde duruyormuş
  gibi hissettiriyor.
- **Denize düşmek zorlaştı.** Eski test `pos.y < 0.15` de diyordu, yani gövdenin
  içinde bir metre düşmek seni güverte hâlâ tepende dururken suya sokuyordu.
  Artık *bordadan* dışarı çıkmak gerekiyor. Ayrıca gövde boyunca bir **sintine
  zemini** var: içeride ayağı kayan, merdiveni ıskalayan ona düşüyor — teknenin
  içinden geçip denize değil.
- **Dümende ileri görüş.** Dümenci camdan 1.23 m geride duruyor ve başının
  üstünde 0.59 m boşluk vardı; sonuç, ekranın üst çeyreğini kaplayan bir tavan
  dilimi. Dümen evi tavanı 5.10 → **5.34**'e çıktı, camlar 1.44 → **1.68 m**
  yükseldi, dümenci de cama yaklaştı. Tavan artık görüş alanına hiç girmiyor.
  Kıç cam da düzeldi: altında tam boy dolu bir panel varmış, cam sahteymiş —
  şimdi gerçekten arkayı görüyorsun.

### Ekrandaki panel

**Tab** paneli açıkken **fare serbest bırakılıyor**: imleç geri geliyor,
bakış ve yürüyüş donuyor, sürgüleri rahatça çekiyorsun. Kapatınca fare
yeniden kameraya geçiyor. Bunu panelin kendisi değil kamera yönetiyor —
imlecin sahibi kim olursa olsun modu geri verecek olan o.

Sol üstte tek bir pano: **gemi durumu**. Çapa ne yapıyor, hangi devre yanıyor,
ve her satırın kendi tuşu yanında. Serbest kamerada gizleniyor. Alttaki tuş
şeridi kaldırıldı — tuşlar zaten bu panelde yazıyor, ikinci kez yazmanın
anlamı yoktu. Menü yok; bir teknenin menüsü olmaz, göz atılacak bir pano olur.

### Dümendeki aletler

Dümenin yanında **fiziksel bir konsol**: pusula (derece + kerteriz), iskandil
(**omurga altı** derinlik — demirleyecek yer ararken önemli olan sayı bu),
parakete (knot) ve zincir boyu. Dört sayı, bir tekneyi sürmekle üstünde yolcu
olmak arasındaki bütün fark.

Ekran arayüzü değil, odanın içinde duran bir panel; yazılar `Label3D`, yani
gerçek metin — viewport yok, doku yok, saniyede dört kez güncelleniyor.
Pirinç kadran yerine sayı, çünkü karanlık bir dümen evinde okunabilen şey o.

### Tavan yüksekliği

İlk denemede dümen evinin iç yüksekliği 1.43 m'ydi; 1.74 m'lik bir adam orada
kafasını çatının içine sokuyordu. Kamara 1.90 m'ye, dümen evi 2.02 m'ye
çıkarıldı ve çatı, korkuluk, merdiven, baca, direk feneri — hepsi buna göre
kaydırıldı. `CEILINGS` ile `FLOORS` arasındaki fark artık gerçek bir insan
boyundan büyük; yoksa tavan çözümü zemin çözümüyle kavga ediyor ve göz
çatının üstüne çıkıyor.

## Teknik

### Dalgalar — FFT

Dalga alanı her karede GPU'da **ters Fourier dönüşümüyle** üretiliyor
(`scripts/wave/`, `shaders/compute/`). FFT hattı
[GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves)'den uyarlandı
(Ethan Truong, MIT — lisans `shaders/compute/` içinde); bu projeye özgü
eklemeler cascade başına spektral bant sınırlama ve CPU geri okuma yolu.

- **TMA/JONSWAP spektrumu + Hasselmann yönsel dağılımı**, Stockham FFT compute
  shader'ında, cascade başına 256². Eski hâli 40 analitik Gerstner bileşeniydi:
  yönsel dağılım bileşen başına tek rastgele açıydı, yani denizin kırk tepe
  yönü vardı — sürekli bir dağılım değil. Yarım metrenin altındaki her şey de
  pruvanın altında **1.3 m'de tekrarlayan** bir normal map'ti.
- **Dört cascade**, tile boyları 503 / 127 / 31 / 7.3 m. Tek bir tile bir
  okyanusu taşıyamaz: 300 m'lik ölü dalgaya yetecek kadar uzun bir tile'ın
  texel'i metrelerce olur, kılcal dalgaya yetecek kadar ince olanı birkaç
  metrede tekrarlar. Her cascade bir oktav bandı sahiplenir
  (`WaveGenerator._assign_bands`). Tile boyları kasten birbirinin ikinin kuvveti
  katı değil — ölçülebilir tile'lar tekrarlarını hizalayıp suya ızgara basar.
- **Bant sınırlama şart**: bant sınırı olmadan her cascade bütün spektrumu
  taşır, aynı ölü dalga dört kez toplanır ve deniz dört kat dik çıkar.
- Genlikler gerçek **belirgin dalga yüksekliğine (Hs)** normalize edilir:
  `WaveGenerator._normalise()` her cascade'in bandı üzerinden TMA varyansını
  sayısal olarak integre eder ve JONSWAP `alpha`'sını ölçekler. Yükseklik
  kaydırıcısı böylece fiziksel bir çarpan, keyfi bir kazanç değil.
  Doğrulama: hedef Hs 2.31 m → ölçülen alan 2.23 m.
- **LOD bant kesimi mesafeye bağlı**, halkaya değil (`cascade_fade`). Quad'ı
  9 m olan bir ağ 4 m'lik dalgayı taşıyamaz; vertex akışına sokmak sadece
  kaynayan geometri üretir — eski "her halka kırk bileşeni de çizer" hâlinin
  yaptığı tam olarak buydu. Kesim halka başına yapılırsa iki halkanın
  buluştuğu sınırda yüzey basamaklanır; mesafe sürekli olduğu için sınırda iki
  halka aynı değeri okur ve dikiş kapanır. Düşen cascade **kaybolmaz**:
  fragment aşaması bütün cascade'lerin eğimini yine örnekler, yani o dalgalar
  aydınlatmaya ve köpüğe katkı vermeye devam eder — sadece sığmadıkları
  geometriyi kımıldatmayı bırakırlar.

**CPU/GPU senkronu.** Bu projenin varlık sebebi olan "sandal gördüğü dalganın
üstünde yüzer" sözleşmesi FFT'yle ölmedi, yer değiştirdi: `cpu_sample.glsl`
vertex shader'ın yer değiştirdiği **aynı texel'leri** 64²'lik bir tampona
indirir, `ocean.gd` onu `buffer_get_data_async` ile okur. Alan tile boyunca
periyodik olduğundan bu kaba ızgara alanın *tamamıdır*, sadece düşük çözünürlüklü;
düşen şey santimetre bandı ve dört buçuk tonluk bir tekne iki santimlik dalgayı
hissedemez. Ayrı tohumlanmış bir CPU dalga seti kullanmak — tek alternatif —
bunu yapamazdı: FFT rastgele Gauss realizasyonudur, birkaç Gerstner bileşeniyle
fazı tutturulamaz, ve tekne tepedeyken pruva çukurda kalırdı.

### Suyun optiği

Işığın gerçekten izlediği sırayla:

1. **Yansıma** — iki katman. (a) Gökyüzü shader'ının gövdesi
   `sky_common.gdshaderinc`'te paylaşılır; su, `reflect(V, N)` yönünde *aynı*
   gökyüzünü örnekler. (b) Gökyüzü olmayan her şey (tekne, şamandıra, enkaz,
   fener) için **planar yansıma**: bir SubViewport'ta, kamera su yüzeyine göre
   aynalanmış halde ikinci kez render edilir; alfa kanalı "burada gerçek bir
   şey yansıyor" maskesidir, boş kalan yerde analitik gökyüzü devam eder.
   Maske olarak alfa **ve parlaklık** birlikte kullanılıyor: additive çizilen
   şeyler (fener huzmesi, fener camı) renk ekler ama alfa yazmaz, sadece alfaya
   bakınca denizdeki tek ışık suya hiç düşmüyordu.
   Ayna düzlemi **y = 0 değil, kameranın altındaki su yüksekliği**: 4.5 m'lik
   bir denizde tekne zamanının yarısını metrelerce alçakta geçirir, y = 0'a
   göre aynalamak her yansımayı metrelerce kaydırıyordu.
2. **Kırılma** — ekran dokusundan normal kaymasıyla; önde kalan nesneler
   siluetlerini suya bulaştırmasın diye derinlik testiyle reddedilir.
3. **Soğurma** — `DEPTH_TEXTURE`'dan gerçek su kalınlığı üzerinden kanal başına
   Beer-Lambert. Kırmızı ~1.5 m'de, mavi ~10 m'de ölür; bulanıklık yağmur ve
   fırtınayla artar.
4. **Saçılma** — su gövdesinin kendi albedosu, motor tarafından aydınlatılır.
5. **Tepe altı geçirgenlik** — güneş dalganın arkasındayken tepenin ışıması.
6. **Köpük** — artık **gerçek bir birikim tamponu**. FFT unpack pass'i her
   karede yüzeyin katlandığı yerde (Jacobian eşiğin altına düştüğünde) köpük
   ekler ve her yerde üstel olarak söndürür; sonuç normal map'in alfa kanalında
   yaşar. Eski hâli gecikmeli ikinci bir Jacobian örneğiydi — vertex başına
   fazladan 18 iterasyon, ve `foam_lag`'ten uzun iz bırakamıyordu.
   Eşik (`whitecap`) rüzgârla ölçüldü: 10/14/19 m/s'de sırasıyla
   **%2 / %8 / %20** kaplama. Köpüğün bütün gürültü örneklemesi
   rüzgârla sürüklenen bir çerçevede yapılır (Stokes sürüklenmesi, rüzgârın
   ~%3'ü), böylece köpük suyun üstünde *yüzer*, üstüne boyanmış durmaz.
7. **Yağmur** — damla halkaları yüzey normaline eklenir (hücre tabanlı, iki
   döndürülmüş kafes, hücrelerin bir kısmı aktif — düzenli ızgara okunmasın
   diye). Şiddetli yağmur ayrıca kılcal dalgayı bastırır: `mss` ve normal
   şiddeti düşer, deniz matlaşır.

Yansıma ve geçen ışık `EMISSION`'a, su gövdesi ve köpük `ALBEDO`'ya gider:
ikisini birden ALBEDO'ya vermek motorun üstüne bir Lambert terimi daha
eklemesine ve denizin griye kaçmasına yol açıyordu.

### Parlaklık ve ölçek

- **Cox-Munk ortalama eğim karesi (mss)** roughness'a beslenir. Çizemeyecek
  kadar küçülen chop yok sayılmaz, eğim varyansı olarak geri döner — güneşe
  doğru uzanan **parıltı yolu** budur. Eski kod detayı 280 m'de sıfırlıyor ve
  ufku aynaya çeviriyordu.
- Güneşe 0.53° açısal genişlik verildi; parıltının yumuşaklığı bundan gelir.
- **Dünya eğriliği** vertex shader'da: 2 m göz yüksekliğinde ufuk ~5 km'de.
  Deniz plakası 14 km'ye uzanır, kamera far düzlemi 18 km.
- Bloom açık (glint'ler bloom olmadan tek gri piksel olarak okunur), tonemap
  **Filmic** — AgX'in highlight roll-off'u daha iyi ama bu sahne her yerde
  0.01-0.05 lineer, AgX'in toe'su geceyi tamamen siyah yapıyor.

### Dalga-nesne etkileşimi

- **Sığlaşma (Green yasası)** — dip yükseldikçe dalga yavaşlar, kısalır ve
  büyür; `H/d` 0.78'i geçince kırılır ve köpürür. Aynı çarpan CPU tarafındaki
  `get_height()`'a da uygulanır, yoksa sandal sığlıkta gördüğü dalganın
  üstünde yüzmez.
- **Yüzen cisimler** — tekne, şamandıra ve enkaz kendilerini `register_floater`
  ile kaydeder; su hattında ince bir kılcal halka ve bir tutam köpük bırakırlar.
  Yer değiştirme çukuru bilerek yok: birkaç santimlik bir çukur görünmez ama
  eğimi metrelerce genişlikte soluk bir disk basıyor (su, sıyırma açılarında
  ayna gibi davranıyor).
- **Dalga öz-gölgelemesi** — güneş alçaldıkça tepeler arkalarındaki çukurları
  karartır. Olmayınca alçak güneş denizin her yerini eşit aydınlatıyor ve
  yüzey "gölgelendirilmiş bir düzlem" gibi okunuyor.

### Akıntı

Kıyı suyu durmaz: akar, döner ve dip yükseldiği her yerde hızlanır.

- Alan bir **akım fonksiyonunun** dik gradyanından türetiliyor, yani inşaat
  gereği ıraksamasız. Su yoktan var olup yok olmuyor, dönüyor — düzgün girdaplar
  çıkıyor, her şeyin aynı yöne kaydığı bir kayış değil.
- **Gelgit**: alan `TIDE_PERIOD` boyunca sinüsle işaret değiştiriyor. Tam
  cezirden tam meddine, arada durgun su.
- **Süreklilik**: aynı hacim daha sığ bir boğazdan geçerken hızlanmak zorunda.
  Bu yüzden akıntı sığlıkların ve burunların üstünde kuvvetleniyor.
- **Tekne suya karşı sürükleniyor**, yere karşı değil. Tek kelimelik fark ama
  bütün gelgit akıntısı bu: limana burnunu dönük tutup üç knotluk çapraz akıntıya
  girersen limanın akıntı altına varırsın.
- Enkaz ve köpük de akıntıyla gidiyor (köpük gürültüsü sürüklenen bir çerçevede
  örnekleniyor).
- **Akıntı çırpıntısı**: hızlı akıntı sığlığın üstünden geçerken yüzeyi kısa ve
  dik hâle getirip köpüğü çizgiler hâlinde yırtar. Bir tekneden akıntıyı gözle
  görünür kılan tek şey budur — akış yönünde uzatılmış köpük şeritleri ve o
  bölgede artan eğim varyansı olarak çiziliyor.

### Hava, iz ve sıçrama

- **Volumetrik sis** — bulut aralıklarından ışık huzmeleri, şimşek çakınca
  hacimsel parlama. Froxel hacmi kısa tutuldu; uzun tutulunca küçük bir engel
  (sandal, sprey) denize sert kenarlı bir gölge kaması basıyor.
- **Kelvin izi** — hıza bağlı olmayan 19.47° kama içinde enine + ıraksak dalga
  aileleri. Beyaz köpük kamanın tamamını değil, sadece kıçtan çıkan dar
  çalkantı izini ve kama kenarındaki kırılma çizgisini kaplar.
  İz teknenin anlık yönüne değil, **geçtiği yola** oturur: sandalın son ~50 m'lik
  rotası 2.5 m aralıklarla örneklenip shader'a veriliyor, `along`/`lat` bu
  poliçizgiye göre ölçülüyor. Yöne kilitlendiğinde dümen kırar kırmaz bütün kama
  tekneyle birlikte dönüp yana kayıyordu; artık kök hep kıçta kalıyor, arkası
  teknenin çizdiği yayı takip ediyor. Örnekler zamanla değil mesafeyle
  alınıyor (yavaş sürüklenen bir tekne izi doldurmasın diye) ve kayıtlı hız
  ~7 s'lik bir sabitle sönümleniyor — iz dağılır.
- **Spindrift** — 11 m/s üstünde yüzeyden koparılan sürekli su tozu; ayrıca
  CPU'da Jacobian taranarak gerçekten kırılan tepede sprey patlaması.
- Sıçrama sistemi: suya düşen her şey damlacık + köpük üretir; gövde içinde su
  asla görünmez (shader maskesi).
- **Islak gövde** — su hattının altında ahşap koyulaşır ve parlar; hızlı
  gidince veya deniz kabarınca üst bordalar da ıslak kalır, sonra yavaşça kurur.
- **Sıçrama halkası** — suya düşen her şey genişleyen bir köpük halkası bırakır
  (havuzlanmış `splash_disk`), damlacıklara ek olarak.

### Deniz tabanı

- 640 m yakın ızgara + 2048 m tek heightmap. Adacıklar iki aşamalı damgalanır:
  önce geniş bir sığlık, sonra tepesine cay. Tek aşamalı damga, teksel
  boyutundan (2.7 m) küçük yarıçapla -28 m'den +1.5 m'ye çıkan 30 m'lik iğneler
  üretiyordu — su opakken görünmüyordu, saydam olunca ortaya çıktı.
- Adacıklar iki aşamalı damgalanır ve en az 4 teksel yarıçapa zorlanır.
- Kostikler gürültü tabanlı, ölçeği ve hızı deniz durumundan türetiliyor.
  Fiziksel doğrusu (dalga alanının eğriliğini suyun içinden aşağı yansıtıp
  Jacobian'ını okumak) `wave_common.gdshaderinc` içindeki `wave_focus()` olarak
  duruyor; ölçümde kare bütçesinin yarısına mal olduğu için kapalı.

### Su altı

- Snell penceresi ve tam iç yansıma: aşağıdan bakınca bütün gökyüzü 97°'lik bir
  koniye sıkışır, dışında yüzey aynaya döner.
- Yüzeyden inen ışık huzmeleri gerçek güneş yönüne bakar (ekran uzayına
  projekte edilir), derinlikle söner.
- Askıda zerreler + yükselen kabarcıklar.

### Gökyüzü

- İki bulut katmanı, farklı yükseklikte projekte edilir; kafanı çevirince
  birbirine göre kayarlar (paralaks). Su yansıması tek katman kullanır —
  `sky_color()` deniz shader'ının en pahalı çağrısı.
- Yıldızlar hücre içinde rastgele konumlanır ve parlaklıkları güç yasasıyla
  dağılır; eskiden ızgaraya kilitliydi.

### Performans notları

Kare maliyeti çözünürlükle ölçekleniyor, yani darboğaz su shader'ının fragment
tarafı. En pahalı satır `sky_color()`'dı: gök kubbe için üç adet 5 oktavlı FBM
mantıklı, ama deniz ekranın çoğunu kaplıyor ve yansıması zaten dalga eğimiyle
bulanık. Deniz artık tek 3 oktavlı FBM kullanıyor, domain warp yok, bulut
gölgelemesi aynı gürültüyü tekrar kullanıyor.

Diğer kesintiler: santimetre ölçekli normal katmanı ve yağmur halkaları sadece
yakın alanda örnekleniyor; gecikmeli köpük Jacobian'ı 40 yerine 18 bileşen
kullanıyor (dalga seti genliğe göre sıralı, yani ilk 18 enerjinin çoğu); uzak
halkalar seyreltildi; planar yansıma 1/3 çözünürlükte ve iki karede bir
yenileniyor (bu kadar pürüzlü bir yüzeyde tek kare gecikme görünmüyor).

CPU tarafında yüzdürme değerlendiricisi düzleştirilmiş `PackedFloat32Array`
tablolarına taşındı, normal artık üç `get_height()` farkıyla değil tek geçişte
analitik hesaplanıyor, ve genliği bir santimin altındaki bileşenler CPU'da
atlanıyor (bir sandalı kımıldatamazlar; GPU hepsini çizmeye devam ediyor).

En büyük tek kazanç gökyüzünün radiance küpüydü. `Sky.PROCESS_MODE_REALTIME`
her karede gökyüzünü 256x256x6 bir küp haritaya (ve bütün mip'lerine) yeniden
çiziyor, yani pahalı bulut shader'ını ~400 bin piksel daha çalıştırıyordu.
Bunu tüketen hiçbir şey yok: ambient bir renkten geliyor, reflection probe yok,
SSR kapalı, geriye sadece çok pürüzlü ahşap ve metalin speküleri kalıyor.
`INCREMENTAL` + 128 ile 1440p'de ölçülen kazanç yaklaşık iki kat.

Benzer israflar: su shader'ı ekran dokusunu `filter_linear_mipmap` ile
istiyordu, bu da her kare ekranın bütün mip zincirini kurduruyordu; detay
normal örneklemeleri 260 m ötede sıfırla çarpılıyor ama yine de yapılıyordu;
köpük gürültüsü köpük olmayan yerde de üç kez örnekleniyordu; derinlik ve ekran
okumaları, suyun zaten her şeyi yuttuğu açık denizde de yapılıyordu. Hepsi
artık kapılı — görüntüde hiçbir değişiklik yok.

Ölçüm uyarısı: bu makinede aynı yapı koşudan koşuya 45–70 FPS arası okuyor,
yani mutlak sayılara güvenilmez. Ayrıca oyunun ilk 2-3 saniyesi shader derleme
yüzünden gerçekten yavaş; FPS sayacına ısındıktan sonra bakmak lazım.

### Bilinen sınırlar

- CPU aynası 64²/cascade ve bir geri okuma gecikmesi geride. Hs ölçümü bu
  yüzden GPU alanının ~%5 altında okuyor (kutu filtresi en kısa cascade'in bir
  kısmını yiyor); yüzdürme için önemsiz, kalibrasyon okurken akılda tutulmalı.
- Cascade sayısı dörtle sınırlı (`MAX_CASCADES`) ve tile boyları elle seçildi.
- En ince cascade 1 m'de kesiliyor (`SHORTEST_WAVE`); altındaki her şey hâlâ
  döşenen detay normal map'lerinden geliyor.
- Deniz durumu hâlâ anlık: kaydırıcı oynayınca Hs zıplar. Gerçek deniz yeni
  rüzgâra onlarca dakikada kurulur ve swell rüzgârı geçirir.
- Planar yansıma tek düzlemli: yüzey o düzlemden uzaklaştıkça yansıma sönümlenip
  yerini analitik gökyüzüne bırakır. Tepe ve çukurda birkaç piksel kayar.
- Dalga refraksiyonu yok: tepeler kıyıya paralel dönmez, sadece sığlaşıp kırılır.
- Fiziksel kostikler (`wave_focus()`) yazılı ama kapalı; ölçümde pahalıydı.
