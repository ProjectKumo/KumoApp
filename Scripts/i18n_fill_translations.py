#!/usr/bin/env python3
"""
KumoApp i18n Translation Filler
Reads Localizable.xcstrings and fills in missing translations.

Usage:
    python3 i18n_fill_translations.py \
        --input Sources/KumoCoreKit/Resources/Localizable.xcstrings \
        --output Sources/KumoCoreKit/Resources/Localizable.xcstrings
"""
import json
import argparse
from pathlib import Path

# Languages to support (add new ones here)
ALL_LANGUAGES = [
    "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es",
    "it", "pt", "ru", "ar", "tr", "vi", "th", "id", "pl", "nl",
]

# Brand / technical names that should NOT be translated
BRAND_NAMES = {
    "Kumo", "Mihomo", "Sub-Store", "ClashMeta", "Surge",
    "GitHub", "GitHub Releases", "ProjectKumo", "gVisor",
    "usekumo.app", "Apple", "macOS", "VPN", "TCP", "UDP",
    "HTTP", "HTTPS", "DNS", "TUN", "PAC", "TLS", "QUIC",
    "LRU", "ARC", "YAML", "JSON", "CIDR", "IP", "IPv6",
    "GeoIP", "GeoSite", "MMDB", "ASN", "DAT", "Gist",
    "Sub-Store", "SubStore", "CLI", "UI", "URL",
}

def is_brand_name(text: str) -> bool:
    """Check if text is primarily a brand/technical name."""
    words = text.split()
    # If all words are brand names, don't translate
    if all(w in BRAND_NAMES or w.rstrip("s") in BRAND_NAMES for w in words):
        return True
    # If text starts with a brand name and is short
    if words and words[0] in BRAND_NAMES and len(words) <= 3:
        return True
    return False

# Translation dictionary for common UI terms.
# Keys are English terms, values are dicts mapping language code to translation.
# For missing languages, the English key is used as fallback.
TRANSLATIONS = {
    "About Kumo": {
        "zh-Hans": "关于 Kumo", "zh-Hant": "關於 Kumo", "ja": "Kumo について",
        "ko": "Kumo 정보", "de": "Über Kumo", "fr": "À propos de Kumo",
        "es": "Acerca de Kumo", "it": "Informazioni su Kumo", "pt": "Sobre o Kumo",
        "ru": "О Kumo", "ar": "حول Kumo", "tr": "Kumo Hakkında",
        "vi": "Về Kumo", "th": "เกี่ยวกับ Kumo", "id": "Tentang Kumo",
        "pl": "O Kumo", "nl": "Over Kumo",
    },
    "Active": {
        "zh-Hans": "活跃", "zh-Hant": "活躍", "ja": "アクティブ", "ko": "활성",
        "de": "Aktiv", "fr": "Actif", "es": "Activo", "it": "Attivo",
        "pt": "Ativo", "ru": "Активный", "ar": "نشط", "tr": "Aktif",
        "vi": "Đang hoạt động", "th": "ใช้งานอยู่", "id": "Aktif",
        "pl": "Aktywny", "nl": "Actief",
    },
    "Add": {
        "zh-Hans": "添加", "zh-Hant": "新增", "ja": "追加", "ko": "추가",
        "de": "Hinzufügen", "fr": "Ajouter", "es": "Añadir", "it": "Aggiungi",
        "pt": "Adicionar", "ru": "Добавить", "ar": "إضافة", "tr": "Ekle",
        "vi": "Thêm", "th": "เพิ่ม", "id": "Tambah", "pl": "Dodaj", "nl": "Toevoegen",
    },
    "Add Defaults": {
        "zh-Hans": "添加默认值", "zh-Hant": "新增預設值", "ja": "デフォルトを追加",
        "ko": "기본값 추가", "de": "Standards hinzufügen", "fr": "Ajouter les valeurs par défaut",
        "es": "Añadir valores por defecto", "it": "Aggiungi predefiniti", "pt": "Adicionar padrões",
        "ru": "Добавить значения по умолчанию", "ar": "إضافة القيم الافتراضية", "tr": "Varsayılanları Ekle",
        "vi": "Thêm mặc định", "th": "เพิ่มค่าเริ่มต้น", "id": "Tambah Default",
        "pl": "Dodaj domyślne", "nl": "Standaarden toevoegen",
    },
    "Add Operator": {
        "zh-Hans": "添加操作符", "zh-Hant": "新增運算子", "ja": "オペレータを追加",
        "ko": "연산자 추가", "de": "Operator hinzufügen", "fr": "Ajouter un opérateur",
        "es": "Añadir operador", "it": "Aggiungi operatore", "pt": "Adicionar operador",
        "ru": "Добавить оператор", "ar": "إضافة عامل", "tr": "Operatör Ekle",
        "vi": "Thêm toán tử", "th": "เพิ่มตัวดำเนินการ", "id": "Tambah Operator",
        "pl": "Dodaj operator", "nl": "Operator toevoegen",
    },
    "Advanced": {
        "zh-Hans": "高级", "zh-Hant": "進階", "ja": "詳細", "ko": "고급",
        "de": "Erweitert", "fr": "Avancé", "es": "Avanzado", "it": "Avanzate",
        "pt": "Avançado", "ru": "Расширенные", "ar": "متقدم", "tr": "Gelişmiş",
        "vi": "Nâng cao", "th": "ขั้นสูง", "id": "Lanjutan", "pl": "Zaawansowane",
        "nl": "Geavanceerd",
    },
    "Agents": {
        "zh-Hans": "代理", "zh-Hant": "代理", "ja": "エージェント", "ko": "에이전트",
        "de": "Agenten", "fr": "Agents", "es": "Agentes", "it": "Agenti",
        "pt": "Agentes", "ru": "Агенты", "ar": "الوكلاء", "tr": "Ajanlar",
        "vi": "Tác nhân", "th": "เอเยนต์", "id": "Agen", "pl": "Agenci", "nl": "Agenten",
    },
    "Allow LAN": {
        "zh-Hans": "允许局域网", "zh-Hant": "允許區域網路", "ja": "LAN を許可",
        "ko": "LAN 허용", "de": "LAN erlauben", "fr": "Autoriser le LAN",
        "es": "Permitir LAN", "it": "Consenti LAN", "pt": "Permitir LAN",
        "ru": "Разрешить LAN", "ar": "السماح للشبكة المحلية", "tr": "LAN'a İzin Ver",
        "vi": "Cho phép LAN", "th": "อนุญาต LAN", "id": "Izinkan LAN",
        "pl": "Zezwól na LAN", "nl": "LAN toestaan",
    },
    "Allow LAN access": {
        "zh-Hans": "允许局域网访问", "zh-Hant": "允許區域網路存取", "ja": "LAN アクセスを許可",
        "ko": "LAN 접근 허용", "de": "LAN-Zugriff erlauben", "fr": "Autoriser l'accès LAN",
        "es": "Permitir acceso LAN", "it": "Consenti accesso LAN", "pt": "Permitir acesso LAN",
        "ru": "Разрешить доступ к LAN", "ar": "السماح بالوصول إلى الشبكة المحلية", "tr": "LAN Erişimine İzin Ver",
        "vi": "Cho phép truy cập LAN", "th": "อนุญาตการเข้าถึง LAN", "id": "Izinkan Akses LAN",
        "pl": "Zezwól na dostęp LAN", "nl": "LAN-toegang toestaan",
    },
    "Apply": {
        "zh-Hans": "应用", "zh-Hant": "套用", "ja": "適用", "ko": "적용",
        "de": "Anwenden", "fr": "Appliquer", "es": "Aplicar", "it": "Applica",
        "pt": "Aplicar", "ru": "Применить", "ar": "تطبيق", "tr": "Uygula",
        "vi": "Áp dụng", "th": "นำไปใช้", "id": "Terapkan", "pl": "Zastosuj", "nl": "Toepassen",
    },
    "Auto": {
        "zh-Hans": "自动", "zh-Hant": "自動", "ja": "自動", "ko": "자동",
        "de": "Auto", "fr": "Auto", "es": "Auto", "it": "Auto",
        "pt": "Auto", "ru": "Авто", "ar": "تلقائي", "tr": "Otomatik",
        "vi": "Tự động", "th": "อัตโนมัติ", "id": "Otomatis", "pl": "Auto", "nl": "Auto",
    },
    "Auto Detect Interface": {
        "zh-Hans": "自动检测接口", "zh-Hant": "自動偵測介面", "ja": "インターフェースを自動検出",
        "ko": "인터페이스 자동 감지", "de": "Schnittstelle automatisch erkennen",
        "fr": "Détection automatique de l'interface", "es": "Detectar interfaz automáticamente",
        "it": "Rileva interfaccia automaticamente", "pt": "Detectar interface automaticamente",
        "ru": "Автоопределение интерфейса", "ar": "اكتشاف الواجهة تلقائياً", "tr": "Arayüzü Otomatik Algıla",
        "vi": "Tự động phát hiện giao diện", "th": "ตรวจหาอินเทอร์เฟซอัตโนมัติ", "id": "Deteksi Antarmuka Otomatis",
        "pl": "Automatyczne wykrywanie interfejsu", "nl": "Interface automatisch detecteren",
    },
    "Auto Route": {
        "zh-Hans": "自动路由", "zh-Hant": "自動路由", "ja": "自動ルーティング",
        "ko": "자동 라우팅", "de": "Automatische Route", "fr": "Routage automatique",
        "es": "Ruta automática", "it": "Instradamento automatico", "pt": "Roteamento automático",
        "ru": "Автоматическая маршрутизация", "ar": "توجيه تلقائي", "tr": "Otomatik Yönlendirme",
        "vi": "Định tuyến tự động", "th": "เส้นทางอัตโนมัติ", "id": "Rute Otomatis",
        "pl": "Automatyczna trasa", "nl": "Automatische route",
    },
    "Auto Sync": {
        "zh-Hans": "自动同步", "zh-Hant": "自動同步", "ja": "自動同期",
        "ko": "자동 동기화", "de": "Automatische Synchronisation", "fr": "Synchronisation automatique",
        "es": "Sincronización automática", "it": "Sincronizzazione automatica", "pt": "Sincronização automática",
        "ru": "Автоматическая синхронизация", "ar": "مزامنة تلقائية", "tr": "Otomatik Senkronizasyon",
        "vi": "Đồng bộ tự động", "th": "ซิงค์อัตโนมัติ", "id": "Sinkronisasi Otomatis",
        "pl": "Automatyczna synchronizacja", "nl": "Automatische synchronisatie",
    },
    "Auto Update": {
        "zh-Hans": "自动更新", "zh-Hant": "自動更新", "ja": "自動更新",
        "ko": "자동 업데이트", "de": "Automatisches Update", "fr": "Mise à jour automatique",
        "es": "Actualización automática", "it": "Aggiornamento automatico", "pt": "Atualização automática",
        "ru": "Автоматическое обновление", "ar": "تحديث تلقائي", "tr": "Otomatik Güncelleme",
        "vi": "Tự động cập nhật", "th": "อัปเดตอัตโนมัติ", "id": "Pembaruan Otomatis",
        "pl": "Automatyczna aktualizacja", "nl": "Automatische update",
    },
    "Back": {
        "zh-Hans": "返回", "zh-Hant": "返回", "ja": "戻る", "ko": "뒤로",
        "de": "Zurück", "fr": "Retour", "es": "Atrás", "it": "Indietro",
        "pt": "Voltar", "ru": "Назад", "ar": "رجوع", "tr": "Geri",
        "vi": "Quay lại", "th": "ย้อนกลับ", "id": "Kembali", "pl": "Wstecz", "nl": "Terug",
    },
    "Behavior": {
        "zh-Hans": "行为", "zh-Hant": "行為", "ja": "動作", "ko": "동작",
        "de": "Verhalten", "fr": "Comportement", "es": "Comportamiento", "it": "Comportamento",
        "pt": "Comportamento", "ru": "Поведение", "ar": "السلوك", "tr": "Davranış",
        "vi": "Hành vi", "th": "พฤติกรรม", "id": "Perilaku", "pl": "Zachowanie", "nl": "Gedrag",
    },
    "Blacklist": {
        "zh-Hans": "黑名单", "zh-Hant": "黑名單", "ja": "ブラックリスト", "ko": "블랙리스트",
        "de": "Blacklist", "fr": "Liste noire", "es": "Lista negra", "it": "Blacklist",
        "pt": "Lista negra", "ru": "Чёрный список", "ar": "القائمة السوداء", "tr": "Kara Liste",
        "vi": "Danh sách đen", "th": "บัญชีดำ", "id": "Daftar Hitam", "pl": "Czarna lista", "nl": "Blacklist",
    },
    "Bypass": {
        "zh-Hans": "绕过", "zh-Hant": "繞過", "ja": "バイパス", "ko": "우회",
        "de": "Umgehen", "fr": "Contourner", "es": "Evitar", "it": "Bypass",
        "pt": "Ignorar", "ru": "Обход", "ar": "تجاوز", "tr": "Atla",
        "vi": "Bỏ qua", "th": "ข้าม", "id": "Lewati", "pl": "Omiń", "nl": "Omzeilen",
    },
    "Cache Algorithm": {
        "zh-Hans": "缓存算法", "zh-Hant": "快取演算法", "ja": "キャッシュアルゴリズム",
        "ko": "캐시 알고리즘", "de": "Cache-Algorithmus", "fr": "Algorithme de cache",
        "es": "Algoritmo de caché", "it": "Algoritmo cache", "pt": "Algoritmo de cache",
        "ru": "Алгоритм кэширования", "ar": "خوارزمية التخزين المؤقت", "tr": "Önbellek Algoritması",
        "vi": "Thuật toán bộ nhớ đệm", "th": "อัลกอริทึมแคช", "id": "Algoritma Cache",
        "pl": "Algorytm pamięci podręcznej", "nl": "Cache-algoritme",
    },
    "Cancel": {
        "zh-Hans": "取消", "zh-Hant": "取消", "ja": "キャンセル", "ko": "취소",
        "de": "Abbrechen", "fr": "Annuler", "es": "Cancelar", "it": "Annulla",
        "pt": "Cancelar", "ru": "Отмена", "ar": "إلغاء", "tr": "İptal",
        "vi": "Hủy", "th": "ยกเลิก", "id": "Batal", "pl": "Anuluj", "nl": "Annuleren",
    },
    "Choose": {
        "zh-Hans": "选择", "zh-Hant": "選擇", "ja": "選択", "ko": "선택",
        "de": "Auswählen", "fr": "Choisir", "es": "Elegir", "it": "Scegli",
        "pt": "Escolher", "ru": "Выбрать", "ar": "اختر", "tr": "Seç",
        "vi": "Chọn", "th": "เลือก", "id": "Pilih", "pl": "Wybierz", "nl": "Kiezen",
    },
    "Clear": {
        "zh-Hans": "清除", "zh-Hant": "清除", "ja": "クリア", "ko": "지우기",
        "de": "Löschen", "fr": "Effacer", "es": "Borrar", "it": "Cancella",
        "pt": "Limpar", "ru": "Очистить", "ar": "مسح", "tr": "Temizle",
        "vi": "Xóa", "th": "ล้าง", "id": "Bersihkan", "pl": "Wyczyść", "nl": "Wissen",
    },
    "Close All": {
        "zh-Hans": "全部关闭", "zh-Hant": "全部關閉", "ja": "すべて閉じる",
        "ko": "모두 닫기", "de": "Alle schließen", "fr": "Tout fermer",
        "es": "Cerrar todo", "it": "Chiudi tutto", "pt": "Fechar tudo",
        "ru": "Закрыть всё", "ar": "إغلاق الكل", "tr": "Tümünü Kapat",
        "vi": "Đóng tất cả", "th": "ปิดทั้งหมด", "id": "Tutup Semua",
        "pl": "Zamknij wszystko", "nl": "Alles sluiten",
    },
    "Collection": {
        "zh-Hans": "集合", "zh-Hant": "集合", "ja": "コレクション", "ko": "컬렉션",
        "de": "Sammlung", "fr": "Collection", "es": "Colección", "it": "Raccolta",
        "pt": "Coleção", "ru": "Коллекция", "ar": "مجموعة", "tr": "Koleksiyon",
        "vi": "Bộ sưu tập", "th": "ชุดรวม", "id": "Koleksi", "pl": "Kolekcja", "nl": "Collectie",
    },
    "Content": {
        "zh-Hans": "内容", "zh-Hant": "內容", "ja": "コンテンツ", "ko": "내용",
        "de": "Inhalt", "fr": "Contenu", "es": "Contenido", "it": "Contenuto",
        "pt": "Conteúdo", "ru": "Содержимое", "ar": "المحتوى", "tr": "İçerik",
        "vi": "Nội dung", "th": "เนื้อหา", "id": "Konten", "pl": "Zawartość", "nl": "Inhoud",
    },
    "Copy": {
        "zh-Hans": "复制", "zh-Hant": "複製", "ja": "コピー", "ko": "복사",
        "de": "Kopieren", "fr": "Copier", "es": "Copiar", "it": "Copia",
        "pt": "Copiar", "ru": "Копировать", "ar": "نسخ", "tr": "Kopyala",
        "vi": "Sao chép", "th": "คัดลอก", "id": "Salin", "pl": "Kopiuj", "nl": "Kopiëren",
    },
    "Core Binary": {
        "zh-Hans": "核心二进制", "zh-Hant": "核心二進位", "ja": "コアバイナリ",
        "ko": "코어 바이너리", "de": "Core-Binärdatei", "fr": "Binaire du noyau",
        "es": "Binario del núcleo", "it": "Binario core", "pt": "Binário do núcleo",
        "ru": "Бинарный файл ядра", "ar": "الملف الثنائي للنواة", "tr": "Çekirdek İkili Dosyası",
        "vi": "Tệp nhị phân lõi", "th": "ไบนารีของแกนกลาง", "id": "Biner Inti",
        "pl": "Binarny plik rdzenia", "nl": "Core-binary",
    },
    "Create": {
        "zh-Hans": "创建", "zh-Hant": "建立", "ja": "作成", "ko": "생성",
        "de": "Erstellen", "fr": "Créer", "es": "Crear", "it": "Crea",
        "pt": "Criar", "ru": "Создать", "ar": "إنشاء", "tr": "Oluştur",
        "vi": "Tạo", "th": "สร้าง", "id": "Buat", "pl": "Utwórz", "nl": "Maken",
    },
    "Debug": {
        "zh-Hans": "调试", "zh-Hant": "偵錯", "ja": "デバッグ", "ko": "디버그",
        "de": "Debug", "fr": "Déboguer", "es": "Depurar", "it": "Debug",
        "pt": "Depurar", "ru": "Отладка", "ar": "تصحيح", "tr": "Hata Ayıklama",
        "vi": "Gỡ lỗi", "th": "แก้ไขข้อบกพร่อง", "id": "Debug", "pl": "Debugowanie",
        "nl": "Debug",
    },
    "Default": {
        "zh-Hans": "默认", "zh-Hant": "預設", "ja": "デフォルト", "ko": "기본",
        "de": "Standard", "fr": "Par défaut", "es": "Por defecto", "it": "Predefinito",
        "pt": "Padrão", "ru": "По умолчанию", "ar": "افتراضي", "tr": "Varsayılan",
        "vi": "Mặc định", "th": "ค่าเริ่มต้น", "id": "Default", "pl": "Domyślny",
        "nl": "Standaard",
    },
    "Delete": {
        "zh-Hans": "删除", "zh-Hant": "刪除", "ja": "削除", "ko": "삭제",
        "de": "Löschen", "fr": "Supprimer", "es": "Eliminar", "it": "Elimina",
        "pt": "Excluir", "ru": "Удалить", "ar": "حذف", "tr": "Sil",
        "vi": "Xóa", "th": "ลบ", "id": "Hapus", "pl": "Usuń", "nl": "Verwijderen",
    },
    "Details": {
        "zh-Hans": "详情", "zh-Hant": "詳情", "ja": "詳細", "ko": "상세 정보",
        "de": "Details", "fr": "Détails", "es": "Detalles", "it": "Dettagli",
        "pt": "Detalhes", "ru": "Подробности", "ar": "التفاصيل", "tr": "Detaylar",
        "vi": "Chi tiết", "th": "รายละเอียด", "id": "Detail", "pl": "Szczegóły",
        "nl": "Details",
    },
    "Done": {
        "zh-Hans": "完成", "zh-Hant": "完成", "ja": "完了", "ko": "완료",
        "de": "Fertig", "fr": "Terminé", "es": "Listo", "it": "Fatto",
        "pt": "Concluído", "ru": "Готово", "ar": "تم", "tr": "Tamam",
        "vi": "Xong", "th": "เสร็จสิ้น", "id": "Selesai", "pl": "Gotowe", "nl": "Klaar",
    },
    "Edit": {
        "zh-Hans": "编辑", "zh-Hant": "編輯", "ja": "編集", "ko": "편집",
        "de": "Bearbeiten", "fr": "Modifier", "es": "Editar", "it": "Modifica",
        "pt": "Editar", "ru": "Изменить", "ar": "تحرير", "tr": "Düzenle",
        "vi": "Chỉnh sửa", "th": "แก้ไข", "id": "Sunting", "pl": "Edytuj", "nl": "Bewerken",
    },
    "Enable": {
        "zh-Hans": "启用", "zh-Hant": "啟用", "ja": "有効化", "ko": "활성화",
        "de": "Aktivieren", "fr": "Activer", "es": "Habilitar", "it": "Abilita",
        "pt": "Ativar", "ru": "Включить", "ar": "تفعيل", "tr": "Etkinleştir",
        "vi": "Bật", "th": "เปิดใช้งาน", "id": "Aktifkan", "pl": "Włącz", "nl": "Inschakelen",
    },
    "Enabled": {
        "zh-Hans": "已启用", "zh-Hant": "已啟用", "ja": "有効", "ko": "활성화됨",
        "de": "Aktiviert", "fr": "Activé", "es": "Habilitado", "it": "Abilitato",
        "pt": "Ativado", "ru": "Включено", "ar": "مفعل", "tr": "Etkin",
        "vi": "Đã bật", "th": "เปิดใช้งานแล้ว", "id": "Diaktifkan", "pl": "Włączone",
        "nl": "Ingeschakeld",
    },
    "Error": {
        "zh-Hans": "错误", "zh-Hant": "錯誤", "ja": "エラー", "ko": "오류",
        "de": "Fehler", "fr": "Erreur", "es": "Error", "it": "Errore",
        "pt": "Erro", "ru": "Ошибка", "ar": "خطأ", "tr": "Hata",
        "vi": "Lỗi", "th": "ข้อผิดพลาด", "id": "Kesalahan", "pl": "Błąd", "nl": "Fout",
    },
    "Fake IP": {
        "zh-Hans": "Fake IP", "zh-Hant": "Fake IP", "ja": "Fake IP", "ko": "Fake IP",
        "de": "Fake-IP", "fr": "IP fictive", "es": "IP falsa", "it": "IP fittizio",
        "pt": "IP falso", "ru": "Поддельный IP", "ar": "IP وهمية", "tr": "Sahte IP",
        "vi": "IP giả", "th": "IP ปลอม", "id": "IP Palsu", "pl": "Fałszywy IP",
        "nl": "Fake IP",
    },
    "Fake IP Filter": {
        "zh-Hans": "Fake IP 过滤", "zh-Hant": "Fake IP 過濾", "ja": "Fake IP フィルタ",
        "ko": "Fake IP 필터", "de": "Fake-IP-Filter", "fr": "Filtre IP fictive",
        "es": "Filtro de IP falsa", "it": "Filtro IP fittizio", "pt": "Filtro de IP falso",
        "ru": "Фильтр поддельного IP", "ar": "مرشح IP الوهمية", "tr": "Sahte IP Filtresi",
        "vi": "Bộ lọc IP giả", "th": "ตัวกรอง IP ปลอม", "id": "Filter IP Palsu",
        "pl": "Filtr fałszywego IP", "nl": "Fake IP-filter",
    },
    "Fake IP Filter Mode": {
        "zh-Hans": "Fake IP 过滤模式", "zh-Hant": "Fake IP 過濾模式", "ja": "Fake IP フィルタモード",
        "ko": "Fake IP 필터 모드", "de": "Fake-IP-Filtermodus", "fr": "Mode de filtre IP fictive",
        "es": "Modo de filtro de IP falsa", "it": "Modalità filtro IP fittizio",
        "pt": "Modo de filtro de IP falso", "ru": "Режим фильтра поддельного IP",
        "ar": "وضع مرشح IP الوهمية", "tr": "Sahte IP Filtre Modu",
        "vi": "Chế độ lọc IP giả", "th": "โหมดตัวกรอง IP ปลอม", "id": "Mode Filter IP Palsu",
        "pl": "Tryb filtra fałszywego IP", "nl": "Fake IP-filtermodus",
    },
    "Fake IP Range": {
        "zh-Hans": "Fake IP 范围", "zh-Hant": "Fake IP 範圍", "ja": "Fake IP レンジ",
        "ko": "Fake IP 범위", "de": "Fake-IP-Bereich", "fr": "Plage IP fictive",
        "es": "Rango de IP falsa", "it": "Intervallo IP fittizio", "pt": "Intervalo de IP falso",
        "ru": "Диапазон поддельного IP", "ar": "نطاق IP الوهمية", "tr": "Sahte IP Aralığı",
        "vi": "Dải IP giả", "th": "ช่วง IP ปลอม", "id": "Rentang IP Palsu",
        "pl": "Zakres fałszywego IP", "nl": "Fake IP-bereik",
    },
    "Fallback": {
        "zh-Hans": "Fallback", "zh-Hant": "Fallback", "ja": "フォールバック",
        "ko": "폴백", "de": "Fallback", "fr": "Fallback", "es": "Fallback",
        "it": "Fallback", "pt": "Fallback", "ru": "Резервный", "ar": "احتياطي",
        "tr": "Yedek", "vi": "Dự phòng", "th": "สำรอง", "id": "Fallback",
        "pl": "Zapasowy", "nl": "Fallback",
    },
    "Fallback Filter": {
        "zh-Hans": "Fallback 过滤", "zh-Hant": "Fallback 過濾", "ja": "フォールバックフィルタ",
        "ko": "폴백 필터", "de": "Fallback-Filter", "fr": "Filtre de fallback",
        "es": "Filtro de fallback", "it": "Filtro fallback", "pt": "Filtro de fallback",
        "ru": "Фильтр резервного", "ar": "مرشح احتياطي", "tr": "Yedek Filtre",
        "vi": "Bộ lọc dự phòng", "th": "ตัวกรองสำรอง", "id": "Filter Fallback",
        "pl": "Filtr zapasowy", "nl": "Fallback-filter",
    },
    "File": {
        "zh-Hans": "文件", "zh-Hant": "檔案", "ja": "ファイル", "ko": "파일",
        "de": "Datei", "fr": "Fichier", "es": "Archivo", "it": "File",
        "pt": "Arquivo", "ru": "Файл", "ar": "ملف", "tr": "Dosya",
        "vi": "Tệp", "th": "ไฟล์", "id": "Berkas", "pl": "Plik", "nl": "Bestand",
    },
    "Format": {
        "zh-Hans": "格式", "zh-Hant": "格式", "ja": "フォーマット", "ko": "형식",
        "de": "Format", "fr": "Format", "es": "Formato", "it": "Formato",
        "pt": "Formato", "ru": "Формат", "ar": "تنسيق", "tr": "Biçim",
        "vi": "Định dạng", "th": "รูปแบบ", "id": "Format", "pl": "Format",
        "nl": "Formaat",
    },
    "From Sub-Store": {
        "zh-Hans": "来自 Sub-Store", "zh-Hant": "來自 Sub-Store", "ja": "Sub-Store から",
        "ko": "Sub-Store에서", "de": "Aus Sub-Store", "fr": "Depuis Sub-Store",
        "es": "Desde Sub-Store", "it": "Da Sub-Store", "pt": "Do Sub-Store",
        "ru": "Из Sub-Store", "ar": "من Sub-Store", "tr": "Sub-Store'dan",
        "vi": "Từ Sub-Store", "th": "จาก Sub-Store", "id": "Dari Sub-Store",
        "pl": "Z Sub-Store", "nl": "Van Sub-Store",
    },
    "General": {
        "zh-Hans": "通用", "zh-Hant": "一般", "ja": "一般", "ko": "일반",
        "de": "Allgemein", "fr": "Général", "es": "General", "it": "Generale",
        "pt": "Geral", "ru": "Общие", "ar": "عام", "tr": "Genel",
        "vi": "Chung", "th": "ทั่วไป", "id": "Umum", "pl": "Ogólne", "nl": "Algemeen",
    },
    "Geo Data": {
        "zh-Hans": "Geo 数据", "zh-Hant": "Geo 資料", "ja": "Geo データ",
        "ko": "Geo 데이터", "de": "Geo-Daten", "fr": "Données Geo",
        "es": "Datos Geo", "it": "Dati Geo", "pt": "Dados Geo",
        "ru": "Geo-данные", "ar": "بيانات Geo", "tr": "Geo Verileri",
        "vi": "Dữ liệu Geo", "th": "ข้อมูล Geo", "id": "Data Geo",
        "pl": "Dane Geo", "nl": "Geo-gegevens",
    },
    "GeoIP DAT Mode": {
        "zh-Hans": "GeoIP DAT 模式", "zh-Hant": "GeoIP DAT 模式", "ja": "GeoIP DAT モード",
        "ko": "GeoIP DAT 모드", "de": "GeoIP-DAT-Modus", "fr": "Mode GeoIP DAT",
        "es": "Modo GeoIP DAT", "it": "Modalità GeoIP DAT", "pt": "Modo GeoIP DAT",
        "ru": "Режим GeoIP DAT", "ar": "وضع GeoIP DAT", "tr": "GeoIP DAT Modu",
        "vi": "Chế độ GeoIP DAT", "th": "โหมด GeoIP DAT", "id": "Mode GeoIP DAT",
        "pl": "Tryb GeoIP DAT", "nl": "GeoIP DAT-modus",
    },
    "Hosts": {
        "zh-Hans": "Hosts", "zh-Hant": "Hosts", "ja": "Hosts", "ko": "Hosts",
        "de": "Hosts", "fr": "Hôtes", "es": "Hosts", "it": "Host",
        "pt": "Hosts", "ru": "Хосты", "ar": "المضيفون", "tr": "Hostlar",
        "vi": "Máy chủ", "th": "โฮสต์", "id": "Host", "pl": "Hosty", "nl": "Hosts",
    },
    "Import": {
        "zh-Hans": "导入", "zh-Hant": "匯入", "ja": "インポート", "ko": "가져오기",
        "de": "Importieren", "fr": "Importer", "es": "Importar", "it": "Importa",
        "pt": "Importar", "ru": "Импортировать", "ar": "استيراد", "tr": "İçe Aktar",
        "vi": "Nhập", "th": "นำเข้า", "id": "Impor", "pl": "Importuj", "nl": "Importeren",
    },
    "Info": {
        "zh-Hans": "信息", "zh-Hant": "資訊", "ja": "情報", "ko": "정보",
        "de": "Info", "fr": "Info", "es": "Información", "it": "Info",
        "pt": "Informações", "ru": "Информация", "ar": "معلومات", "tr": "Bilgi",
        "vi": "Thông tin", "th": "ข้อมูล", "id": "Info", "pl": "Informacje",
        "nl": "Info",
    },
    "Install": {
        "zh-Hans": "安装", "zh-Hant": "安裝", "ja": "インストール", "ko": "설치",
        "de": "Installieren", "fr": "Installer", "es": "Instalar", "it": "Installa",
        "pt": "Instalar", "ru": "Установить", "ar": "تثبيت", "tr": "Kur",
        "vi": "Cài đặt", "th": "ติดตั้ง", "id": "Pasang", "pl": "Zainstaluj",
        "nl": "Installeren",
    },
    "JavaScript": {
        "zh-Hans": "JavaScript", "zh-Hant": "JavaScript", "ja": "JavaScript",
        "ko": "JavaScript", "de": "JavaScript", "fr": "JavaScript", "es": "JavaScript",
        "it": "JavaScript", "pt": "JavaScript", "ru": "JavaScript", "ar": "JavaScript",
        "tr": "JavaScript", "vi": "JavaScript", "th": "JavaScript", "id": "JavaScript",
        "pl": "JavaScript", "nl": "JavaScript",
    },
    "Key": {
        "zh-Hans": "键", "zh-Hant": "鍵", "ja": "キー", "ko": "키",
        "de": "Schlüssel", "fr": "Clé", "es": "Clave", "it": "Chiave",
        "pt": "Chave", "ru": "Ключ", "ar": "مفتاح", "tr": "Anahtar",
        "vi": "Khóa", "th": "คีย์", "id": "Kunci", "pl": "Klucz", "nl": "Sleutel",
    },
    "LAN": {
        "zh-Hans": "局域网", "zh-Hant": "區域網路", "ja": "LAN", "ko": "LAN",
        "de": "LAN", "fr": "Réseau local", "es": "LAN", "it": "LAN",
        "pt": "LAN", "ru": "LAN", "ar": "الشبكة المحلية", "tr": "LAN",
        "vi": "Mạng LAN", "th": "LAN", "id": "LAN", "pl": "LAN", "nl": "LAN",
    },
    "Level": {
        "zh-Hans": "级别", "zh-Hant": "層級", "ja": "レベル", "ko": "수준",
        "de": "Stufe", "fr": "Niveau", "es": "Nivel", "it": "Livello",
        "pt": "Nível", "ru": "Уровень", "ar": "المستوى", "tr": "Seviye",
        "vi": "Cấp độ", "th": "ระดับ", "id": "Tingkat", "pl": "Poziom",
        "nl": "Niveau",
    },
    "Local": {
        "zh-Hans": "本地", "zh-Hant": "本地", "ja": "ローカル", "ko": "로컬",
        "de": "Lokal", "fr": "Local", "es": "Local", "it": "Locale",
        "pt": "Local", "ru": "Локальный", "ar": "محلي", "tr": "Yerel",
        "vi": "Cục bộ", "th": "ภายในเครื่อง", "id": "Lokal", "pl": "Lokalny",
        "nl": "Lokaal",
    },
    "Log Level": {
        "zh-Hans": "日志级别", "zh-Hant": "日誌層級", "ja": "ログレベル",
        "ko": "로그 수준", "de": "Log-Level", "fr": "Niveau de journalisation",
        "es": "Nivel de registro", "it": "Livello log", "pt": "Nível de log",
        "ru": "Уровень логирования", "ar": "مستوى السجل", "tr": "Günlük Seviyesi",
        "vi": "Mức độ nhật ký", "th": "ระดับบันทึก", "id": "Tingkat Log",
        "pl": "Poziom logów", "nl": "Logniveau",
    },
    "Mixed": {
        "zh-Hans": "混合", "zh-Hant": "混合", "ja": "混合", "ko": "혼합",
        "de": "Gemischt", "fr": "Mixte", "es": "Mixto", "it": "Misto",
        "pt": "Misto", "ru": "Смешанный", "ar": "مختلط", "tr": "Karışık",
        "vi": "Hỗn hợp", "th": "ผสม", "id": "Campuran", "pl": "Mieszany",
        "nl": "Gemengd",
    },
    "More": {
        "zh-Hans": "更多", "zh-Hant": "更多", "ja": "その他", "ko": "더보기",
        "de": "Mehr", "fr": "Plus", "es": "Más", "it": "Altro",
        "pt": "Mais", "ru": "Ещё", "ar": "المزيد", "tr": "Daha Fazla",
        "vi": "Thêm", "th": "เพิ่มเติม", "id": "Lainnya", "pl": "Więcej", "nl": "Meer",
    },
    "Name": {
        "zh-Hans": "名称", "zh-Hant": "名稱", "ja": "名前", "ko": "이름",
        "de": "Name", "fr": "Nom", "es": "Nombre", "it": "Nome",
        "pt": "Nome", "ru": "Имя", "ar": "الاسم", "tr": "İsim",
        "vi": "Tên", "th": "ชื่อ", "id": "Nama", "pl": "Nazwa", "nl": "Naam",
    },
    "Nameserver": {
        "zh-Hans": "Nameserver", "zh-Hant": "Nameserver", "ja": "ネームサーバー",
        "ko": "네임서버", "de": "Nameserver", "fr": "Serveur de noms",
        "es": "Servidor de nombres", "it": "Nameserver", "pt": "Servidor de nomes",
        "ru": "Сервер имён", "ar": "خادم الأسماء", "tr": "Ad Sunucusu",
        "vi": "Máy chủ tên miền", "th": "เซิร์ฟเวอร์ชื่อ", "id": "Nameserver",
        "pl": "Serwer nazw", "nl": "Nameserver",
    },
    "Nameserver Policy": {
        "zh-Hans": "Nameserver 策略", "zh-Hant": "Nameserver 策略", "ja": "ネームサーバーポリシー",
        "ko": "네임서버 정책", "de": "Nameserver-Richtlinie", "fr": "Politique de serveur de noms",
        "es": "Política de servidor de nombres", "it": "Politica nameserver",
        "pt": "Política de servidor de nomes", "ru": "Политика сервера имён",
        "ar": "سياسة خادم الأسماء", "tr": "Ad Sunucusu Politikası",
        "vi": "Chính sách máy chủ tên miền", "th": "นโยบายเซิร์ฟเวอร์ชื่อ",
        "id": "Kebijakan Nameserver", "pl": "Polityka serwera nazw", "nl": "Nameserver-beleid",
    },
    "New": {
        "zh-Hans": "新建", "zh-Hant": "新增", "ja": "新規", "ko": "새로 만들기",
        "de": "Neu", "fr": "Nouveau", "es": "Nuevo", "it": "Nuovo",
        "pt": "Novo", "ru": "Создать", "ar": "جديد", "tr": "Yeni",
        "vi": "Mới", "th": "ใหม่", "id": "Baru", "pl": "Nowy", "nl": "Nieuw",
    },
    "None": {
        "zh-Hans": "无", "zh-Hant": "無", "ja": "なし", "ko": "없음",
        "de": "Keine", "fr": "Aucun", "es": "Ninguno", "it": "Nessuno",
        "pt": "Nenhum", "ru": "Нет", "ar": "لا شيء", "tr": "Yok",
        "vi": "Không", "th": "ไม่มี", "id": "Tidak ada", "pl": "Brak", "nl": "Geen",
    },
    "Normal": {
        "zh-Hans": "正常", "zh-Hant": "正常", "ja": "通常", "ko": "일반",
        "de": "Normal", "fr": "Normal", "es": "Normal", "it": "Normale",
        "pt": "Normal", "ru": "Обычный", "ar": "عادي", "tr": "Normal",
        "vi": "Bình thường", "th": "ปกติ", "id": "Normal", "pl": "Normalny",
        "nl": "Normaal",
    },
    "Open": {
        "zh-Hans": "打开", "zh-Hant": "開啟", "ja": "開く", "ko": "열기",
        "de": "Öffnen", "fr": "Ouvrir", "es": "Abrir", "it": "Apri",
        "pt": "Abrir", "ru": "Открыть", "ar": "فتح", "tr": "Aç",
        "vi": "Mở", "th": "เปิด", "id": "Buka", "pl": "Otwórz", "nl": "Openen",
    },
    "Override": {
        "zh-Hans": "覆写", "zh-Hant": "覆寫", "ja": "オーバーライド",
        "ko": "오버라이드", "de": "Überschreiben", "fr": "Remplacer",
        "es": "Sobrescribir", "it": "Sovrascrivi", "pt": "Substituir",
        "ru": "Переопределить", "ar": "تجاوز", "tr": "Geçersiz Kıl",
        "vi": "Ghi đè", "th": "แทนที่", "id": "Timpa", "pl": "Nadpisz",
        "nl": "Overschrijven",
    },
    "Policy": {
        "zh-Hans": "策略", "zh-Hant": "策略", "ja": "ポリシー", "ko": "정책",
        "de": "Richtlinie", "fr": "Politique", "es": "Política", "it": "Politica",
        "pt": "Política", "ru": "Политика", "ar": "سياسة", "tr": "Politika",
        "vi": "Chính sách", "th": "นโยบาย", "id": "Kebijakan", "pl": "Polityka",
        "nl": "Beleid",
    },
    "Port": {
        "zh-Hans": "端口", "zh-Hant": "連接埠", "ja": "ポート", "ko": "포트",
        "de": "Port", "fr": "Port", "es": "Puerto", "it": "Porta",
        "pt": "Porta", "ru": "Порт", "ar": "منفذ", "tr": "Port",
        "vi": "Cổng", "th": "พอร์ต", "id": "Port", "pl": "Port", "nl": "Poort",
    },
    "Prefer HTTP/3": {
        "zh-Hans": "优先 HTTP/3", "zh-Hant": "優先 HTTP/3", "ja": "HTTP/3 を優先",
        "ko": "HTTP/3 우선", "de": "HTTP/3 bevorzugen", "fr": "Préférer HTTP/3",
        "es": "Preferir HTTP/3", "it": "Preferisci HTTP/3", "pt": "Preferir HTTP/3",
        "ru": "Предпочитать HTTP/3", "ar": "تفضيل HTTP/3", "tr": "HTTP/3 Tercih Et",
        "vi": "Ưu tiên HTTP/3", "th": "ให้ความสำคัญกับ HTTP/3", "id": "Utamakan HTTP/3",
        "pl": "Preferuj HTTP/3", "nl": "HTTP/3 voorkeur",
    },
    "Profile": {
        "zh-Hans": "配置", "zh-Hant": "設定檔", "ja": "プロファイル",
        "ko": "프로필", "de": "Profil", "fr": "Profil", "es": "Perfil",
        "it": "Profilo", "pt": "Perfil", "ru": "Профиль", "ar": "الملف الشخصي",
        "tr": "Profil", "vi": "Hồ sơ", "th": "โปรไฟล์", "id": "Profil",
        "pl": "Profil", "nl": "Profiel",
    },
    "Proxy": {
        "zh-Hans": "代理", "zh-Hant": "代理", "ja": "プロキシ", "ko": "프록시",
        "de": "Proxy", "fr": "Proxy", "es": "Proxy", "it": "Proxy",
        "pt": "Proxy", "ru": "Прокси", "ar": "بروكسي", "tr": "Proxy",
        "vi": "Proxy", "th": "พร็อกซี", "id": "Proksi", "pl": "Proxy",
        "nl": "Proxy",
    },
    "Proxy Server Nameserver": {
        "zh-Hans": "代理服务器 Nameserver", "zh-Hant": "代理伺服器 Nameserver",
        "ja": "プロキシサーバーネームサーバー", "ko": "프록시 서버 네임서버",
        "de": "Proxy-Server-Nameserver", "fr": "Nameserver du serveur proxy",
        "es": "Nameserver del servidor proxy", "it": "Nameserver server proxy",
        "pt": "Nameserver do servidor proxy", "ru": "Nameserver прокси-сервера",
        "ar": "خادم أسماء الخادم الوكيل", "tr": "Proxy Sunucusu Ad Sunucusu",
        "vi": "Máy chủ tên miền máy chủ proxy", "th": "Nameserver เซิร์ฟเวอร์พร็อกซี",
        "id": "Nameserver Server Proxy", "pl": "Nameserver serwera proxy",
        "nl": "Proxyserver-nameserver",
    },
    "Proxy Server Nameserver Policy": {
        "zh-Hans": "代理服务器 Nameserver 策略", "zh-Hant": "代理伺服器 Nameserver 策略",
        "ja": "プロキシサーバーネームサーバーポリシー", "ko": "프록시 서버 네임서버 정책",
        "de": "Proxy-Server-Nameserver-Richtlinie", "fr": "Politique de nameserver du proxy",
        "es": "Política de nameserver del proxy", "it": "Politica nameserver proxy",
        "pt": "Política de nameserver do proxy", "ru": "Политика nameserver прокси",
        "ar": "سياسة خادم أسماء الوكيل", "tr": "Proxy Ad Sunucusu Politikası",
        "vi": "Chính sách máy chủ tên miền proxy", "th": "นโยบาย nameserver พร็อกซี",
        "id": "Kebijakan Nameserver Proxy", "pl": "Polityka nameserver proxy",
        "nl": "Proxy-nameserver-beleid",
    },
    "QUIC": {
        "zh-Hans": "QUIC", "zh-Hant": "QUIC", "ja": "QUIC", "ko": "QUIC",
        "de": "QUIC", "fr": "QUIC", "es": "QUIC", "it": "QUIC",
        "pt": "QUIC", "ru": "QUIC", "ar": "QUIC", "tr": "QUIC",
        "vi": "QUIC", "th": "QUIC", "id": "QUIC", "pl": "QUIC", "nl": "QUIC",
    },
    "Redir Host": {
        "zh-Hans": "Redir Host", "zh-Hant": "Redir Host", "ja": "Redir Host",
        "ko": "Redir Host", "de": "Redir-Host", "fr": "Hôte de redirection",
        "es": "Host de redirección", "it": "Host di reindirizzamento",
        "pt": "Host de redirecionamento", "ru": "Redir-хост", "ar": "مضيف إعادة التوجيه",
        "tr": "Yönlendirme Hostu", "vi": "Máy chủ chuyển hướng", "th": "โฮสต์เปลี่ยนเส้นทาง",
        "id": "Host Redirect", "pl": "Host przekierowania", "nl": "Redir-host",
    },
    "Refresh": {
        "zh-Hans": "刷新", "zh-Hant": "重新整理", "ja": "更新", "ko": "새로고침",
        "de": "Aktualisieren", "fr": "Actualiser", "es": "Actualizar", "it": "Aggiorna",
        "pt": "Atualizar", "ru": "Обновить", "ar": "تحديث", "tr": "Yenile",
        "vi": "Làm mới", "th": "รีเฟรช", "id": "Segarkan", "pl": "Odśwież",
        "nl": "Vernieuwen",
    },
    "Reset": {
        "zh-Hans": "重置", "zh-Hant": "重設", "ja": "リセット", "ko": "재설정",
        "de": "Zurücksetzen", "fr": "Réinitialiser", "es": "Restablecer", "it": "Reimposta",
        "pt": "Redefinir", "ru": "Сбросить", "ar": "إعادة تعيين", "tr": "Sıfırla",
        "vi": "Đặt lại", "th": "รีเซ็ต", "id": "Atur Ulang", "pl": "Resetuj",
        "nl": "Resetten",
    },
    "Restore": {
        "zh-Hans": "恢复", "zh-Hant": "還原", "ja": "復元", "ko": "복원",
        "de": "Wiederherstellen", "fr": "Restaurer", "es": "Restaurar", "it": "Ripristina",
        "pt": "Restaurar", "ru": "Восстановить", "ar": "استعادة", "tr": "Geri Yükle",
        "vi": "Khôi phục", "th": "คืนค่า", "id": "Pulihkan", "pl": "Przywróć",
        "nl": "Herstellen",
    },
    "Retry": {
        "zh-Hans": "重试", "zh-Hant": "重試", "ja": "再試行", "ko": "재시도",
        "de": "Wiederholen", "fr": "Réessayer", "es": "Reintentar", "it": "Riprova",
        "pt": "Tentar novamente", "ru": "Повторить", "ar": "إعادة المحاولة", "tr": "Tekrar Dene",
        "vi": "Thử lại", "th": "ลองใหม่", "id": "Coba Lagi", "pl": "Spróbuj ponownie",
        "nl": "Opnieuw proberen",
    },
    "Routing": {
        "zh-Hans": "路由", "zh-Hant": "路由", "ja": "ルーティング", "ko": "라우팅",
        "de": "Routing", "fr": "Routage", "es": "Enrutamiento", "it": "Instradamento",
        "pt": "Roteamento", "ru": "Маршрутизация", "ar": "التوجيه", "tr": "Yönlendirme",
        "vi": "Định tuyến", "th": "การกำหนดเส้นทาง", "id": "Routing", "pl": "Routing",
        "nl": "Routering",
    },
    "Rule": {
        "zh-Hans": "规则", "zh-Hant": "規則", "ja": "ルール", "ko": "규칙",
        "de": "Regel", "fr": "Règle", "es": "Regla", "it": "Regola",
        "pt": "Regra", "ru": "Правило", "ar": "قاعدة", "tr": "Kural",
        "vi": "Quy tắc", "th": "กฎ", "id": "Aturan", "pl": "Reguła", "nl": "Regel",
    },
    "Save": {
        "zh-Hans": "保存", "zh-Hant": "儲存", "ja": "保存", "ko": "저장",
        "de": "Speichern", "fr": "Enregistrer", "es": "Guardar", "it": "Salva",
        "pt": "Salvar", "ru": "Сохранить", "ar": "حفظ", "tr": "Kaydet",
        "vi": "Lưu", "th": "บันทึก", "id": "Simpan", "pl": "Zapisz", "nl": "Opslaan",
    },
    "Search": {
        "zh-Hans": "搜索", "zh-Hant": "搜尋", "ja": "検索", "ko": "검색",
        "de": "Suchen", "fr": "Rechercher", "es": "Buscar", "it": "Cerca",
        "pt": "Pesquisar", "ru": "Поиск", "ar": "بحث", "tr": "Ara",
        "vi": "Tìm kiếm", "th": "ค้นหา", "id": "Cari", "pl": "Szukaj", "nl": "Zoeken",
    },
    "Select": {
        "zh-Hans": "选择", "zh-Hant": "選擇", "ja": "選択", "ko": "선택",
        "de": "Auswählen", "fr": "Sélectionner", "es": "Seleccionar", "it": "Seleziona",
        "pt": "Selecionar", "ru": "Выбрать", "ar": "اختيار", "tr": "Seç",
        "vi": "Chọn", "th": "เลือก", "id": "Pilih", "pl": "Wybierz", "nl": "Selecteren",
    },
    "Settings": {
        "zh-Hans": "设置", "zh-Hant": "設定", "ja": "設定", "ko": "설정",
        "de": "Einstellungen", "fr": "Paramètres", "es": "Ajustes", "it": "Impostazioni",
        "pt": "Configurações", "ru": "Настройки", "ar": "الإعدادات", "tr": "Ayarlar",
        "vi": "Cài đặt", "th": "การตั้งค่า", "id": "Pengaturan", "pl": "Ustawienia",
        "nl": "Instellingen",
    },
    "Show": {
        "zh-Hans": "显示", "zh-Hant": "顯示", "ja": "表示", "ko": "표시",
        "de": "Anzeigen", "fr": "Afficher", "es": "Mostrar", "it": "Mostra",
        "pt": "Mostrar", "ru": "Показать", "ar": "إظهار", "tr": "Göster",
        "vi": "Hiển thị", "th": "แสดง", "id": "Tampilkan", "pl": "Pokaż", "nl": "Weergeven",
    },
    "Silent": {
        "zh-Hans": "静默", "zh-Hant": "靜默", "ja": "サイレント", "ko": "무음",
        "de": "Leise", "fr": "Silencieux", "es": "Silencioso", "it": "Silenzioso",
        "pt": "Silencioso", "ru": "Бесшумный", "ar": "صامت", "tr": "Sessiz",
        "vi": "Im lặng", "th": "เงียบ", "id": "Senyap", "pl": "Cichy", "nl": "Stil",
    },
    "Skip": {
        "zh-Hans": "跳过", "zh-Hant": "跳過", "ja": "スキップ", "ko": "건너뛰기",
        "de": "Überspringen", "fr": "Ignorer", "es": "Omitir", "it": "Salta",
        "pt": "Pular", "ru": "Пропустить", "ar": "تخطي", "tr": "Atla",
        "vi": "Bỏ qua", "th": "ข้าม", "id": "Lewati", "pl": "Pomiń", "nl": "Overslaan",
    },
    "Start": {
        "zh-Hans": "启动", "zh-Hant": "啟動", "ja": "開始", "ko": "시작",
        "de": "Starten", "fr": "Démarrer", "es": "Iniciar", "it": "Avvia",
        "pt": "Iniciar", "ru": "Запустить", "ar": "بدء", "tr": "Başlat",
        "vi": "Bắt đầu", "th": "เริ่ม", "id": "Mulai", "pl": "Start", "nl": "Starten",
    },
    "Status": {
        "zh-Hans": "状态", "zh-Hant": "狀態", "ja": "ステータス", "ko": "상태",
        "de": "Status", "fr": "État", "es": "Estado", "it": "Stato",
        "pt": "Status", "ru": "Статус", "ar": "الحالة", "tr": "Durum",
        "vi": "Trạng thái", "th": "สถานะ", "id": "Status", "pl": "Status", "nl": "Status",
    },
    "Stop": {
        "zh-Hans": "停止", "zh-Hant": "停止", "ja": "停止", "ko": "중지",
        "de": "Stoppen", "fr": "Arrêter", "es": "Detener", "it": "Ferma",
        "pt": "Parar", "ru": "Остановить", "ar": "إيقاف", "tr": "Durdur",
        "vi": "Dừng", "th": "หยุด", "id": "Berhenti", "pl": "Zatrzymaj", "nl": "Stoppen",
    },
    "Success": {
        "zh-Hans": "成功", "zh-Hant": "成功", "ja": "成功", "ko": "성공",
        "de": "Erfolg", "fr": "Succès", "es": "Éxito", "it": "Successo",
        "pt": "Sucesso", "ru": "Успех", "ar": "نجاح", "tr": "Başarılı",
        "vi": "Thành công", "th": "สำเร็จ", "id": "Berhasil", "pl": "Sukces", "nl": "Succes",
    },
    "Sync": {
        "zh-Hans": "同步", "zh-Hant": "同步", "ja": "同期", "ko": "동기화",
        "de": "Synchronisieren", "fr": "Synchroniser", "es": "Sincronizar", "it": "Sincronizza",
        "pt": "Sincronizar", "ru": "Синхронизировать", "ar": "مزامنة", "tr": "Senkronize Et",
        "vi": "Đồng bộ", "th": "ซิงค์", "id": "Sinkronisasi", "pl": "Synchronizuj",
        "nl": "Synchroniseren",
    },
    "System": {
        "zh-Hans": "系统", "zh-Hant": "系統", "ja": "システム", "ko": "시스템",
        "de": "System", "fr": "Système", "es": "Sistema", "it": "Sistema",
        "pt": "Sistema", "ru": "Система", "ar": "النظام", "tr": "Sistem",
        "vi": "Hệ thống", "th": "ระบบ", "id": "Sistem", "pl": "System", "nl": "Systeem",
    },
    "Tags": {
        "zh-Hans": "标签", "zh-Hant": "標籤", "ja": "タグ", "ko": "태그",
        "de": "Tags", "fr": "Tags", "es": "Etiquetas", "it": "Tag",
        "pt": "Tags", "ru": "Теги", "ar": "الوسوم", "tr": "Etiketler",
        "vi": "Thẻ", "th": "แท็ก", "id": "Tag", "pl": "Tagi", "nl": "Tags",
    },
    "Target": {
        "zh-Hans": "目标", "zh-Hant": "目標", "ja": "ターゲット", "ko": "대상",
        "de": "Ziel", "fr": "Cible", "es": "Objetivo", "it": "Destinazione",
        "pt": "Destino", "ru": "Цель", "ar": "الهدف", "tr": "Hedef",
        "vi": "Mục tiêu", "th": "เป้าหมาย", "id": "Target", "pl": "Cel", "nl": "Doel",
    },
    "Test": {
        "zh-Hans": "测试", "zh-Hant": "測試", "ja": "テスト", "ko": "테스트",
        "de": "Testen", "fr": "Tester", "es": "Probar", "it": "Test",
        "pt": "Testar", "ru": "Проверить", "ar": "اختبار", "tr": "Test Et",
        "vi": "Kiểm tra", "th": "ทดสอบ", "id": "Uji", "pl": "Testuj", "nl": "Testen",
    },
    "Traffic": {
        "zh-Hans": "流量", "zh-Hant": "流量", "ja": "トラフィック", "ko": "트래픽",
        "de": "Datenverkehr", "fr": "Trafic", "es": "Tráfico", "it": "Traffico",
        "pt": "Tráfego", "ru": "Трафик", "ar": "حركة البيانات", "tr": "Trafik",
        "vi": "Lưu lượng", "th": "ปริมาณข้อมูล", "id": "Lalu Lintas", "pl": "Ruch",
        "nl": "Verkeer",
    },
    "Type": {
        "zh-Hans": "类型", "zh-Hant": "類型", "ja": "タイプ", "ko": "유형",
        "de": "Typ", "fr": "Type", "es": "Tipo", "it": "Tipo",
        "pt": "Tipo", "ru": "Тип", "ar": "النوع", "tr": "Tür",
        "vi": "Loại", "th": "ประเภท", "id": "Jenis", "pl": "Typ", "nl": "Type",
    },
    "Uninstall": {
        "zh-Hans": "卸载", "zh-Hant": "解除安裝", "ja": "アンインストール",
        "ko": "제거", "de": "Deinstallieren", "fr": "Désinstaller", "es": "Desinstalar",
        "it": "Disinstalla", "pt": "Desinstalar", "ru": "Удалить", "ar": "إلغاء التثبيت",
        "tr": "Kaldır", "vi": "Gỡ cài đặt", "th": "ถอนการติดตั้ง", "id": "Hapus Instalasi",
        "pl": "Odinstaluj", "nl": "Deïnstalleren",
    },
    "Update": {
        "zh-Hans": "更新", "zh-Hant": "更新", "ja": "更新", "ko": "업데이트",
        "de": "Aktualisieren", "fr": "Mettre à jour", "es": "Actualizar", "it": "Aggiorna",
        "pt": "Atualizar", "ru": "Обновить", "ar": "تحديث", "tr": "Güncelle",
        "vi": "Cập nhật", "th": "อัปเดต", "id": "Perbarui", "pl": "Aktualizuj", "nl": "Bijwerken",
    },
    "Use": {
        "zh-Hans": "使用", "zh-Hant": "使用", "ja": "使用", "ko": "사용",
        "de": "Verwenden", "fr": "Utiliser", "es": "Usar", "it": "Usa",
        "pt": "Usar", "ru": "Использовать", "ar": "استخدام", "tr": "Kullan",
        "vi": "Sử dụng", "th": "ใช้", "id": "Gunakan", "pl": "Użyj", "nl": "Gebruiken",
    },
    "Value": {
        "zh-Hans": "值", "zh-Hant": "值", "ja": "値", "ko": "값",
        "de": "Wert", "fr": "Valeur", "es": "Valor", "it": "Valore",
        "pt": "Valor", "ru": "Значение", "ar": "القيمة", "tr": "Değer",
        "vi": "Giá trị", "th": "ค่า", "id": "Nilai", "pl": "Wartość", "nl": "Waarde",
    },
    "Version": {
        "zh-Hans": "版本", "zh-Hant": "版本", "ja": "バージョン", "ko": "버전",
        "de": "Version", "fr": "Version", "es": "Versión", "it": "Versione",
        "pt": "Versão", "ru": "Версия", "ar": "الإصدار", "tr": "Sürüm",
        "vi": "Phiên bản", "th": "เวอร์ชัน", "id": "Versi", "pl": "Wersja", "nl": "Versie",
    },
    "View": {
        "zh-Hans": "查看", "zh-Hant": "檢視", "ja": "表示", "ko": "보기",
        "de": "Anzeigen", "fr": "Voir", "es": "Ver", "it": "Visualizza",
        "pt": "Ver", "ru": "Просмотр", "ar": "عرض", "tr": "Görüntüle",
        "vi": "Xem", "th": "ดู", "id": "Lihat", "pl": "Widok", "nl": "Bekijken",
    },
    "Warning": {
        "zh-Hans": "警告", "zh-Hant": "警告", "ja": "警告", "ko": "경고",
        "de": "Warnung", "fr": "Avertissement", "es": "Advertencia", "it": "Avviso",
        "pt": "Aviso", "ru": "Предупреждение", "ar": "تحذير", "tr": "Uyarı",
        "vi": "Cảnh báo", "th": "คำเตือน", "id": "Peringatan", "pl": "Ostrzeżenie",
        "nl": "Waarschuwing",
    },
    "Whitelist": {
        "zh-Hans": "白名单", "zh-Hant": "白名單", "ja": "ホワイトリスト",
        "ko": "화이트리스트", "de": "Whitelist", "fr": "Liste blanche", "es": "Lista blanca",
        "it": "Whitelist", "pt": "Lista branca", "ru": "Белый список", "ar": "القائمة البيضاء",
        "tr": "Beyaz Liste", "vi": "Danh sách trắng", "th": "บัญชีขาว", "id": "Daftar Putih",
        "pl": "Biała lista", "nl": "Whitelist",
    },
    "YAML": {
        "zh-Hans": "YAML", "zh-Hant": "YAML", "ja": "YAML", "ko": "YAML",
        "de": "YAML", "fr": "YAML", "es": "YAML", "it": "YAML", "pt": "YAML",
        "ru": "YAML", "ar": "YAML", "tr": "YAML", "vi": "YAML", "th": "YAML",
        "id": "YAML", "pl": "YAML", "nl": "YAML",
    },
}

# Map substrings for pattern-based translation
def translate_key(key: str, lang: str) -> str | None:
    """Try to translate a key using exact match or substring heuristics."""
    # Exact match
    if key in TRANSLATIONS and lang in TRANSLATIONS[key]:
        return TRANSLATIONS[key][lang]

    # Brand names: keep as-is
    if is_brand_name(key):
        return key

    # Substring heuristics for compound phrases
    # Try matching common prefixes/suffixes
    lower_key = key.lower()

    # Patterns like "Enable X" → "启用 X"
    if lower_key.startswith("enable "):
        rest = key[7:]
        rest_tr = translate_key(rest, lang)
        if rest_tr:
            enable_map = {
                "zh-Hans": "启用", "zh-Hant": "啟用", "ja": "有効化", "ko": "활성화",
                "de": "Aktivieren", "fr": "Activer", "es": "Habilitar", "it": "Abilita",
                "pt": "Ativar", "ru": "Включить", "ar": "تفعيل", "tr": "Etkinleştir",
                "vi": "Bật", "th": "เปิดใช้งาน", "id": "Aktifkan", "pl": "Włącz",
                "nl": "Inschakelen",
            }
            return f"{enable_map.get(lang, 'Enable')} {rest_tr}"

    # Patterns like "Use X" → "使用 X"
    if lower_key.startswith("use "):
        rest = key[4:]
        rest_tr = translate_key(rest, lang)
        if rest_tr:
            use_map = {
                "zh-Hans": "使用", "zh-Hant": "使用", "ja": "使用", "ko": "사용",
                "de": "Verwenden", "fr": "Utiliser", "es": "Usar", "it": "Usa",
                "pt": "Usar", "ru": "Использовать", "ar": "استخدام", "tr": "Kullan",
                "vi": "Sử dụng", "th": "ใช้", "id": "Gunakan", "pl": "Użyj",
                "nl": "Gebruiken",
            }
            return f"{use_map.get(lang, 'Use')} {rest_tr}"

    # Patterns with "Copy X" → "复制 X"
    if lower_key.startswith("copy "):
        rest = key[5:]
        rest_tr = translate_key(rest, lang)
        if rest_tr:
            copy_map = {
                "zh-Hans": "复制", "zh-Hant": "複製", "ja": "コピー", "ko": "복사",
                "de": "Kopieren", "fr": "Copier", "es": "Copiar", "it": "Copia",
                "pt": "Copiar", "ru": "Копировать", "ar": "نسخ", "tr": "Kopyala",
                "vi": "Sao chép", "th": "คัดลอก", "id": "Salin", "pl": "Kopiuj",
                "nl": "Kopiëren",
            }
            return f"{copy_map.get(lang, 'Copy')} {rest_tr}"

    return None


def main():
    parser = argparse.ArgumentParser(description="Fill missing i18n translations")
    parser.add_argument("--input", required=True, help="Input .xcstrings file")
    parser.add_argument("--output", required=True, help="Output .xcstrings file")
    parser.add_argument("--dry-run", action="store_true", help="Show stats without writing")
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        catalog = json.load(f)

    strings = catalog.get("strings", {})
    filled_count = 0
    skipped_brand = 0
    skipped_interp = 0
    still_missing = 0

    for key, entry in strings.items():
        localizations = entry.setdefault("localizations", {})

        # Skip interpolated strings (contain \(…))
        if r"\(" in key:
            skipped_interp += 1
            continue

        for lang in ALL_LANGUAGES:
            if lang in localizations:
                continue

            translation = translate_key(key, lang)
            if translation:
                localizations[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": translation,
                    }
                }
                filled_count += 1
            elif is_brand_name(key):
                localizations[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": key,
                    }
                }
                filled_count += 1
                skipped_brand += 1
            else:
                still_missing += 1

    # Update metadata
    catalog["sourceLanguage"] = "en"

    print(f"Filled translations:     {filled_count}")
    print(f"Skipped (interpolated):  {skipped_interp}")
    print(f"Still missing:           {still_missing}")
    print(f"Total keys:              {len(strings)}")
    print(f"Languages:               {len(ALL_LANGUAGES)}")

    if not args.dry_run:
        with open(args.output, 'w') as f:
            json.dump(catalog, f, indent=2, ensure_ascii=False)
        print(f"\nWritten to {args.output}")


if __name__ == "__main__":
    main()
