class_name FirebaseConfig
## Firebase ayarları. Bu değerler gizli değildir; erişimi firebase/database.rules.json kuralları korur.

## Realtime Database adresi (sonunda / olmadan).
const DB_URL := "https://craftmine-aa35b-default-rtdb.europe-west1.firebasedatabase.app"

## Firebase Console > Proje ayarları > Genel > "Web API Key".
## Boş bırakılırsa anonim giriş yapılmaz; bu durumda veritabanı kuralları herkese açık olmalıdır.
const API_KEY := ""
