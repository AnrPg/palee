defmodule Palee.Automations.Domain.RecipeTexts do
  @moduledoc """
  ADR-346: each recipe's default subject and text in every app language,
  and how a text is filled in. Pure.

  A box may replace the text with its own (one text, in the box's words and
  language); the default follows each person's language. Placeholders, in
  braces: `{first_name}`, `{box}`, and per recipe `{days}` (missed
  classes), `{package}` and `{ends_on}` (renewal reminder). Unknown
  placeholders are refused when a box saves its text, and anything left
  unfilled is removed when sending.
  """

  @placeholders ~w(first_name box days package ends_on)
  @max_subject 120
  @max_body 1_000

  @texts %{
    "welcome" => %{
      "en" => {"Welcome to {box}", "Hi {first_name}, welcome to {box}! We're glad you're here. See you in class."},
      "el" => {"Καλώς ήρθες στο {box}", "Γεια σου {first_name}, καλώς ήρθες στο {box}! Χαιρόμαστε που είσαι εδώ. Τα λέμε στο τμήμα."},
      "de" => {"Willkommen bei {box}", "Hallo {first_name}, willkommen bei {box}! Schön, dass du da bist. Bis bald im Kurs."},
      "fr" => {"Bienvenue chez {box}", "Bonjour {first_name}, bienvenue chez {box} ! Ravis de t'accueillir. À bientôt en cours."},
      "es" => {"Bienvenido a {box}", "Hola {first_name}, ¡bienvenido a {box}! Nos alegra tenerte aquí. Nos vemos en clase."},
      "it" => {"Benvenuto in {box}", "Ciao {first_name}, benvenuto in {box}! Siamo felici di averti qui. Ci vediamo a lezione."},
      "nl" => {"Welkom bij {box}", "Hoi {first_name}, welkom bij {box}! Fijn dat je er bent. Tot in de les."},
      "pt-PT" => {"Bem-vindo ao {box}", "Olá {first_name}, bem-vindo ao {box}! Ficamos contentes por estares cá. Até à aula."},
      "ru" => {"Добро пожаловать в {box}", "Привет, {first_name}! Добро пожаловать в {box}. Рады, что ты с нами. До встречи на занятии."},
      "bg" => {"Добре дошли в {box}", "Здравей, {first_name}! Добре дошъл в {box}. Радваме се, че си тук. До скоро в часа."},
      "ar" => {"مرحبًا بك في {box}", "مرحبًا {first_name}، أهلًا بك في {box}! يسعدنا وجودك معنا. نراك في الحصة."},
      "he" => {"ברוכים הבאים ל-{box}", "היי {first_name}, ברוך הבא ל-{box}! שמחים שהצטרפת. נתראה בשיעור."}
    },
    "trial_follow_up" => %{
      "en" => {"How was your trial class?", "Hi {first_name}, thanks for trying a class at {box}. Want to keep going? Reply and we'll find the right subscription package for you."},
      "el" => {"Πώς σου φάνηκε το δοκιμαστικό;", "Γεια σου {first_name}, ευχαριστούμε που δοκίμασες ένα τμήμα στο {box}. Θέλεις να συνεχίσεις; Απάντησε και θα βρούμε μαζί το πακέτο συνδρομής που σου ταιριάζει."},
      "de" => {"Wie war deine Probestunde?", "Hallo {first_name}, danke, dass du bei {box} eine Probestunde gemacht hast. Möchtest du weitermachen? Antworte uns und wir finden das passende Abo-Paket."},
      "fr" => {"Comment s'est passé ton cours d'essai ?", "Bonjour {first_name}, merci d'avoir essayé un cours chez {box}. Envie de continuer ? Réponds-nous et nous trouverons la formule d'abonnement qui te convient."},
      "es" => {"¿Qué tal tu clase de prueba?", "Hola {first_name}, gracias por probar una clase en {box}. ¿Quieres seguir? Respóndenos y encontraremos el paquete de suscripción adecuado para ti."},
      "it" => {"Com'è andata la lezione di prova?", "Ciao {first_name}, grazie per aver provato una lezione da {box}. Vuoi continuare? Rispondici e troveremo il pacchetto di abbonamento giusto per te."},
      "nl" => {"Hoe was je proefles?", "Hoi {first_name}, bedankt dat je een les bij {box} hebt geprobeerd. Wil je doorgaan? Laat het ons weten en we zoeken het abonnementspakket dat bij je past."},
      "pt-PT" => {"Como correu a tua aula experimental?", "Olá {first_name}, obrigado por experimentares uma aula no {box}. Queres continuar? Responde-nos e encontramos o pacote de subscrição certo para ti."},
      "ru" => {"Как прошло пробное занятие?", "Привет, {first_name}! Спасибо, что попробовал занятие в {box}. Хочешь продолжить? Ответь нам, и мы подберём подходящий абонемент."},
      "bg" => {"Как мина пробният час?", "Здравей, {first_name}! Благодарим, че опита час в {box}. Искаш ли да продължиш? Отговори ни и ще намерим подходящия абонаментен пакет."},
      "ar" => {"كيف كانت حصتك التجريبية؟", "مرحبًا {first_name}، شكرًا لتجربتك حصة في {box}. هل تريد الاستمرار؟ رد علينا وسنجد لك باقة الاشتراك المناسبة."},
      "he" => {"איך היה שיעור הניסיון?", "היי {first_name}, תודה שניסית שיעור ב-{box}. רוצה להמשיך? השב לנו ונמצא יחד את חבילת המנוי המתאימה לך."}
    },
    "missed_classes" => %{
      "en" => {"We miss you at {box}", "Hi {first_name}, we haven't seen you for {days} days. Everything OK? Book your next class whenever you're ready."},
      "el" => {"Μας έλειψες στο {box}", "Γεια σου {first_name}, έχουμε {days} μέρες να σε δούμε. Όλα καλά; Κλείσε το επόμενο τμήμα όποτε είσαι έτοιμος."},
      "de" => {"Wir vermissen dich bei {box}", "Hallo {first_name}, wir haben dich seit {days} Tagen nicht gesehen. Alles okay? Buche deinen nächsten Kurs, wann immer du bereit bist."},
      "fr" => {"Tu nous manques chez {box}", "Bonjour {first_name}, cela fait {days} jours que nous ne t'avons pas vu. Tout va bien ? Réserve ton prochain cours quand tu veux."},
      "es" => {"Te echamos de menos en {box}", "Hola {first_name}, hace {days} días que no te vemos. ¿Todo bien? Reserva tu próxima clase cuando quieras."},
      "it" => {"Ci manchi da {box}", "Ciao {first_name}, non ti vediamo da {days} giorni. Tutto bene? Prenota la prossima lezione quando vuoi."},
      "nl" => {"We missen je bij {box}", "Hoi {first_name}, we hebben je al {days} dagen niet gezien. Alles goed? Boek je volgende les wanneer je er klaar voor bent."},
      "pt-PT" => {"Temos saudades tuas no {box}", "Olá {first_name}, há {days} dias que não te vemos. Está tudo bem? Reserva a próxima aula quando quiseres."},
      "ru" => {"Мы скучаем по тебе в {box}", "Привет, {first_name}! Мы не видели тебя уже {days} дн. Всё в порядке? Запишись на следующее занятие, когда будешь готов."},
      "bg" => {"Липсваш ни в {box}", "Здравей, {first_name}! Не сме те виждали от {days} дни. Всичко наред ли е? Запиши се за следващия час, когато си готов."},
      "ar" => {"نفتقدك في {box}", "مرحبًا {first_name}، لم نرك منذ {days} يومًا. هل كل شيء بخير؟ احجز حصتك القادمة متى كنت جاهزًا."},
      "he" => {"מתגעגעים אליך ב-{box}", "היי {first_name}, לא ראינו אותך כבר {days} ימים. הכול בסדר? הזמן את השיעור הבא מתי שתרצה."}
    },
    "renewal_reminder" => %{
      "en" => {"Your {package} ends on {ends_on}", "Hi {first_name}, your subscription package {package} at {box} ends on {ends_on}. Renew it to keep your place in class."},
      "el" => {"Το {package} λήγει στις {ends_on}", "Γεια σου {first_name}, το πακέτο συνδρομής {package} στο {box} λήγει στις {ends_on}. Ανανέωσέ το για να κρατήσεις τη θέση σου στα τμήματα."},
      "de" => {"Dein {package} endet am {ends_on}", "Hallo {first_name}, dein Abo-Paket {package} bei {box} endet am {ends_on}. Verlängere es, um deinen Platz im Kurs zu behalten."},
      "fr" => {"Ton {package} se termine le {ends_on}", "Bonjour {first_name}, ta formule d'abonnement {package} chez {box} se termine le {ends_on}. Renouvelle-la pour garder ta place en cours."},
      "es" => {"Tu {package} termina el {ends_on}", "Hola {first_name}, tu paquete de suscripción {package} en {box} termina el {ends_on}. Renuévalo para mantener tu plaza en clase."},
      "it" => {"Il tuo {package} scade il {ends_on}", "Ciao {first_name}, il tuo pacchetto di abbonamento {package} da {box} scade il {ends_on}. Rinnovalo per mantenere il tuo posto a lezione."},
      "nl" => {"Je {package} loopt af op {ends_on}", "Hoi {first_name}, je abonnementspakket {package} bij {box} loopt af op {ends_on}. Verleng het om je plek in de les te houden."},
      "pt-PT" => {"O teu {package} termina a {ends_on}", "Olá {first_name}, o teu pacote de subscrição {package} no {box} termina a {ends_on}. Renova-o para manteres o teu lugar nas aulas."},
      "ru" => {"Твой {package} заканчивается {ends_on}", "Привет, {first_name}! Твой абонемент {package} в {box} заканчивается {ends_on}. Продли его, чтобы сохранить место на занятиях."},
      "bg" => {"Твоят {package} изтича на {ends_on}", "Здравей, {first_name}! Абонаментният ти пакет {package} в {box} изтича на {ends_on}. Поднови го, за да запазиш мястото си в часовете."},
      "ar" => {"تنتهي {package} في {ends_on}", "مرحبًا {first_name}، تنتهي باقة اشتراكك {package} في {box} في {ends_on}. جدّدها لتحتفظ بمكانك في الحصص."},
      "he" => {"ה-{package} שלך מסתיים ב-{ends_on}", "היי {first_name}, חבילת המנוי {package} שלך ב-{box} מסתיימת ב-{ends_on}. חדש אותה כדי לשמור על מקומך בשיעורים."}
    },
    "birthday" => %{
      "en" => {"Happy birthday, {first_name}!", "Everyone at {box} wishes you a happy birthday and a strong year ahead!"},
      "el" => {"Χρόνια πολλά, {first_name}!", "Όλοι στο {box} σου ευχόμαστε χρόνια πολλά και μια δυνατή χρονιά!"},
      "de" => {"Alles Gute zum Geburtstag, {first_name}!", "Alle bei {box} wünschen dir alles Gute zum Geburtstag und ein starkes neues Jahr!"},
      "fr" => {"Joyeux anniversaire, {first_name} !", "Toute l'équipe de {box} te souhaite un joyeux anniversaire et une belle année pleine d'énergie !"},
      "es" => {"¡Feliz cumpleaños, {first_name}!", "¡Todo el equipo de {box} te desea un feliz cumpleaños y un año lleno de fuerza!"},
      "it" => {"Buon compleanno, {first_name}!", "Tutti da {box} ti augurano buon compleanno e un anno pieno di energia!"},
      "nl" => {"Gefeliciteerd, {first_name}!", "Iedereen bij {box} wenst je een fijne verjaardag en een sterk nieuw jaar!"},
      "pt-PT" => {"Parabéns, {first_name}!", "Todos no {box} te desejam um feliz aniversário e um ano cheio de força!"},
      "ru" => {"С днём рождения, {first_name}!", "Все в {box} поздравляют тебя с днём рождения и желают сильного года!"},
      "bg" => {"Честит рожден ден, {first_name}!", "Всички в {box} ти пожелаваме честит рожден ден и силна година!"},
      "ar" => {"عيد ميلاد سعيد يا {first_name}!", "يتمنى لك الجميع في {box} عيد ميلاد سعيدًا وعامًا مليئًا بالقوة!"},
      "he" => {"יום הולדת שמח, {first_name}!", "כולם ב-{box} מאחלים לך יום הולדת שמח ושנה חזקה!"}
    },
    "win_back" => %{
      "en" => {"Come back to {box}", "Hi {first_name}, it's been a while. We'd love to see you back at {box}. Reply and we'll help you find a time that works."},
      "el" => {"Γύρνα στο {box}", "Γεια σου {first_name}, πάει καιρός. Θα χαρούμε πολύ να σε ξαναδούμε στο {box}. Απάντησε και θα σε βοηθήσουμε να βρεις ώρα που σε βολεύει."},
      "de" => {"Komm zurück zu {box}", "Hallo {first_name}, es ist eine Weile her. Wir würden dich gern wieder bei {box} sehen. Antworte uns und wir finden eine passende Zeit."},
      "fr" => {"Reviens chez {box}", "Bonjour {first_name}, cela fait un moment. Nous serions ravis de te revoir chez {box}. Réponds-nous et nous t'aiderons à trouver un créneau qui te convient."},
      "es" => {"Vuelve a {box}", "Hola {first_name}, ha pasado un tiempo. Nos encantaría verte de nuevo en {box}. Respóndenos y te ayudamos a encontrar un horario que te venga bien."},
      "it" => {"Torna da {box}", "Ciao {first_name}, è passato un po' di tempo. Ci farebbe piacere rivederti da {box}. Rispondici e ti aiutiamo a trovare un orario comodo."},
      "nl" => {"Kom terug naar {box}", "Hoi {first_name}, het is even geleden. We zien je graag terug bij {box}. Laat het ons weten en we zoeken een tijd die je past."},
      "pt-PT" => {"Volta ao {box}", "Olá {first_name}, já passou algum tempo. Adorávamos ver-te de volta no {box}. Responde-nos e ajudamos-te a encontrar um horário que te dê jeito."},
      "ru" => {"Возвращайся в {box}", "Привет, {first_name}! Давно не виделись. Будем рады снова видеть тебя в {box}. Ответь нам, и мы поможем подобрать удобное время."},
      "bg" => {"Върни се в {box}", "Здравей, {first_name}! Мина известно време. Ще се радваме да те видим отново в {box}. Отговори ни и ще ти помогнем да намериш удобен час."},
      "ar" => {"عُد إلى {box}", "مرحبًا {first_name}، مرّ وقت طويل. يسعدنا أن نراك مجددًا في {box}. رد علينا وسنساعدك في إيجاد وقت يناسبك."},
      "he" => {"חזור ל-{box}", "היי {first_name}, עבר זמן מה. נשמח לראות אותך שוב ב-{box}. השב לנו ונעזור לך למצוא זמן שמתאים לך."}
    }
  }

  def placeholders, do: @placeholders
  def max_subject, do: @max_subject
  def max_body, do: @max_body

  @doc "Every language the defaults are written in."
  def locales, do: @texts |> Map.fetch!("welcome") |> Map.keys() |> Enum.sort()

  @doc "The recipe's default `{subject, body}` in `locale` (English when missing)."
  def default(recipe, locale) do
    texts = Map.fetch!(@texts, recipe)
    Map.get(texts, locale) || Map.get(texts, base(locale)) || Map.fetch!(texts, "en")
  end

  defp base(locale) when is_binary(locale), do: locale |> String.split("-") |> hd()
  defp base(_locale), do: "en"

  @doc """
  A box's own text checked before it is saved: lengths, and only known
  placeholders. `nil` or blank means «back to the default».
  """
  @spec validate(String.t() | nil, :subject | :body) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  def validate(nil, _field), do: {:ok, nil}

  def validate(text, field) when is_binary(text) do
    text = String.trim(text)
    max = if field == :subject, do: @max_subject, else: @max_body

    cond do
      text == "" -> {:ok, nil}
      String.length(text) > max -> {:error, "too_long"}
      unknown_placeholders(text) != [] -> {:error, "unknown_placeholder"}
      true -> {:ok, text}
    end
  end

  def validate(_text, _field), do: {:error, "invalid"}

  defp unknown_placeholders(text) do
    ~r/\{([a-z_]+)\}/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&(&1 in @placeholders))
  end

  @doc "Fills the placeholders; any left without a value are removed."
  def render(text, vars) when is_binary(text) do
    ~r/\{([a-z_]+)\}/
    |> Regex.replace(text, fn _whole, name -> to_string(Map.get(vars, name) || "") end)
    |> String.replace(~r/[ \t]{2,}/u, " ")
    |> String.trim()
  end
end
