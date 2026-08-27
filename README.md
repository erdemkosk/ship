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
| T | İleri taş fırlat |
| Sol tık | Tıklanan noktaya taş bırak |
| Tab | Ayar panelini gizle/göster |

## Sağ panel ayarları

- **Rüzgar Hızı / Yönü** — dalga boyu, yönü ve bulut akışı rüzgardan türetilir
- **Dalga Yüksekliği / Dikliği** — Gerstner dalga genliği ve sertliği
- **Saat** — güneş konumu, gün/gece döngüsü (6 gün doğumu, 18 gün batımı)
- **Sis, Bulut, Yağmur, Fırtına (şimşek)** — atmosfer; bulutlar prosedürel
  gökyüzü shader'ında rüzgarla sürüklenir, gece açık havada yıldızlar çıkar,
  şimşek bulutları içeriden aydınlatır

Hazır ön ayarlar: Sakin Gece, Puslu Akşam, Fırtına, Kâbus.

## Teknik

### Dalgalar

- **Pierson-Moskowitz spektrumu**: 40 Gerstner bileşeni, tepe dalga boyundan
  ~0.55 m'ye kadar logaritmik aralıklı. Kısa bileşenler geniş yönsel dağılımlı
  (kısa tepeli chop), uzunlar dar (uzun tepeli ölü dalga). Ayrıca rüzgârdan 58°
  farklı yönde bağımsız bir **swell** seti — gerçek denizin "geçmişi olan"
  görüntüsü buradan gelir.
- Genlikler gerçek **belirgin dalga yüksekliğine (Hs)** normalize edilir, yani
  yükseklik kaydırıcısı fiziksel bir çarpandır. `SEA_DEVELOPMENT` sınırlı fetch
  varsayar; tam gelişmiş deniz 18 m/s'de Hs ~7 m olurdu.
- Aynı dalga seti GPU'da (vertex shader) ve CPU'da (`_displace`) çalışır, yani
  sandal gördüğün dalganın üstünde yüzer. Ortak matematik
  `shaders/wave_common.gdshaderinc` içinde.

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
6. **Köpük** — yer değiştirmenin **Jacobian determinantı** negatife düştüğü,
   yani yüzeyin katlandığı yerde. Gecikmeli ikinci bir örnek köpüğün kırılan
   dalganın arkasında iz bırakmasını sağlar. Köpüğün bütün gürültü örneklemesi
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

- Spektrum FFT değil, 40 bileşenli analitik Gerstner. FFT daha zengin olurdu
  ama CPU/GPU dalga senkronunu (yüzdürmenin görüntüyle birebir uyması) kırardı.
- Köpük kalıcılığı gerçek bir birikim buffer'ı değil, gecikmeli ikinci örnek.
- Planar yansıma tek düzlemli: yüzey o düzlemden uzaklaştıkça yansıma sönümlenip
  yerini analitik gökyüzüne bırakır. Tepe ve çukurda birkaç piksel kayar.
- Dalga refraksiyonu yok: tepeler kıyıya paralel dönmez, sadece sığlaşıp kırılır.
- Fiziksel kostikler (`wave_focus()`) yazılı ama kapalı; ölçümde pahalıydı.
