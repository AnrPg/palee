defmodule Palee.Repo.Migrations.TrainingQuotesLocaleAndMore do
  @moduledoc """
  The quote on Αρχική was one of 20 English lines, some of them flippant, shown to
  every member whatever their language. Quotes now carry a `locale`
  («el» or «en»; the member's `preferred_locale` picks), the flippant ones
  are retired and a wider list is added. Attributed lines are well-known,
  widely published sayings; the rest are unattributed proverbs of training.
  Idempotent: a quote is added only when its body is not there yet.
  """

  use Ecto.Migration

  @retired [
    "Sweat is just fat crying.",
    "Wake up. Work out. Look hot. Kick ass.",
    "Train insane or remain the same.",
    "The difference between try and triumph is just a little umph.",
    "Success usually comes to those who are too busy to be looking for it.",
    "The only bad workout is the one that didn't happen.",
    "The clock is ticking. Are you becoming the person you want to be?"
  ]

  @en [
    {"We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
     "Will Durant"},
    {"It does not matter how slowly you go as long as you do not stop.", "Confucius"},
    {"The successful warrior is the average man, with laser-like focus.", "Bruce Lee"},
    {"I fear not the man who has practiced 10,000 kicks once, but the man who has practiced one kick 10,000 times.",
     "Bruce Lee"},
    {"It's not whether you get knocked down, it's whether you get up.", "Vince Lombardi"},
    {"The only place where success comes before work is in the dictionary.", "Vidal Sassoon"},
    {"I hated every minute of training, but I said, don't quit. Suffer now and live the rest of your life as a champion.",
     "Muhammad Ali"},
    {"Float like a butterfly, sting like a bee.", "Muhammad Ali"},
    {"Hard work beats talent when talent doesn't work hard.", "Tim Notke"},
    {"You miss 100% of the shots you don't take.", "Wayne Gretzky"},
    {"Whether you think you can, or you think you can't, you're right.", "Henry Ford"},
    {"It always seems impossible until it's done.", "Nelson Mandela"},
    {"The harder the battle, the sweeter the victory.", "Les Brown"},
    {"Success is the sum of small efforts, repeated day in and day out.", "Robert Collier"},
    {"A journey of a thousand miles begins with a single step.", "Lao Tzu"},
    {"He who has a why to live can bear almost any how.", "Friedrich Nietzsche"},
    {"What we achieve inwardly will change outer reality.", "Plutarch"},
    {"No citizen has a right to be an amateur in the matter of physical training.", "Socrates"},
    {"It is a shame for a man to grow old without seeing the beauty and strength of which his body is capable.",
     "Socrates"},
    {"I've failed over and over and over again in my life. And that is why I succeed.",
     "Michael Jordan"},
    {"Everything you've ever wanted is on the other side of fear.", "George Addair"},
    {"Fall seven times, stand up eight.", "Japanese proverb"},
    {"Energy and persistence conquer all things.", "Benjamin Franklin"},
    {"The body achieves what the mind believes.", nil},
    {"Your body can stand almost anything. It's your mind you have to convince.", nil},
    {"Don't stop when you're tired. Stop when you're done.", nil},
    {"It never gets easier. You just get stronger.", nil},
    {"Discipline is doing what needs to be done, even when you don't want to do it.", nil},
    {"No matter how slow you go, you are still lapping everybody on the couch.", nil},
    {"What seems impossible today will one day become your warm-up.", nil},
    {"Small steps every day add up to a different person.", nil},
    {"You don't have to be great to start, but you have to start to be great.", "Zig Ziglar"},
    {"Motivation gets you started. Habit keeps you going.", "Jim Ryun"},
    {"Strength does not come from winning. Your struggles develop your strengths.",
     "Arnold Schwarzenegger"},
    {"The last three or four reps is what makes the muscle grow.", "Arnold Schwarzenegger"},
    {"Rest if you must, but don't quit.", nil},
    {"Today's effort is tomorrow's ease.", nil},
    {"Progress, not perfection.", nil},
    {"The hardest lift of all is lifting your butt off the couch.", nil},
    {"Take care of your body. It's the only place you have to live.", "Jim Rohn"},
    {"Pain is temporary. Pride lasts.", nil},
    {"A year from now you will wish you had started today.", "Karen Lamb"},
    {"Do something today that your future self will thank you for.", nil},
    {"Quality is not an act, it is a habit.", "Aristotle"},
    {"Well begun is half done.", "Aristotle"},
    {"Strong people are harder to kill than weak people and more useful in general.",
     "Mark Rippetoe"},
    {"The pain you feel today will be the strength you feel tomorrow.", nil},
    {"Consistency beats intensity.", nil},
    {"Be stronger than your excuses.", nil},
    {"You are one workout away from a good mood.", nil}
  ]

  @el [
    {"Νους υγιής εν σώματι υγιεί.", "Ιουβενάλης"},
    {"Η υγεία είναι ο μεγαλύτερος πλούτος.", "Ιπποκράτης"},
    {"Ο βίος βραχύς, η δε τέχνη μακρή.", "Ιπποκράτης"},
    {"Ο περπατών, υγιαίνει.", "Ιπποκράτης"},
    {"Γνῶθι σαυτόν.", "Δελφικό ρητό"},
    {"Μηδέν άγαν.", "Δελφικό ρητό"},
    {"Αρχή ήμισυ παντός.", "Αρχαίο ρητό"},
    {"Ἀρχὴ δὲ τοῦ βίου ἡ ἄσκησις.", nil},
    {"Η αρετή είναι συνήθεια, όχι πράξη.", "Αριστοτέλης"},
    {"Είμαστε αυτό που επαναλαμβάνουμε σταθερά. Η αριστεία δεν είναι πράξη, είναι συνήθεια.",
     "Will Durant"},
    {"Καμία πόλη δεν έχει δικαίωμα να είναι ερασιτέχνης στη σωματική άσκηση.", "Σωκράτης"},
    {"Είναι ντροπή για έναν άνθρωπο να γεράσει χωρίς να δει την ομορφιά και τη δύναμη που μπορεί να έχει το σώμα του.",
     "Σωκράτης"},
    {"Ο δρόμος των χιλίων μιλίων αρχίζει με ένα βήμα.", "Λάο Τσε"},
    {"Δεν έχει σημασία πόσο αργά πηγαίνεις, αρκεί να μη σταματάς.", "Κομφούκιος"},
    {"Επτά φορές να πέσεις, οκτώ να σηκωθείς.", "Ιαπωνική παροιμία"},
    {"Σταγόνα τη σταγόνα γεμίζει το ποτάμι.", "Παροιμία"},
    {"Όποιος έχει λόγο να ζει, αντέχει σχεδόν κάθε πώς.", "Φρίντριχ Νίτσε"},
    {"Ό,τι φαίνεται αδύνατο σήμερα, αύριο θα είναι η προθέρμανσή σου.", nil},
    {"Δεν γίνεται πιο εύκολο. Γίνεσαι πιο δυνατός.", nil},
    {"Μην σταματάς όταν κουραστείς. Σταμάτα όταν τελειώσεις.", nil},
    {"Το σώμα σου αντέχει σχεδόν τα πάντα. Το μυαλό σου πρέπει να πείσεις.", nil},
    {"Η πειθαρχία είναι να κάνεις ό,τι πρέπει, ακόμη κι όταν δεν θέλεις.", nil},
    {"Όσο αργά κι αν πηγαίνεις, προσπερνάς όλους όσοι έμειναν στον καναπέ.", nil},
    {"Ο πόνος είναι προσωρινός. Η υπερηφάνεια μένει.", nil},
    {"Η σταθερότητα νικά την ένταση.", nil},
    {"Πρόοδος, όχι τελειότητα.", nil},
    {"Η προσπάθεια σήμερα είναι η ευκολία του αύριο.", nil},
    {"Μικρά βήματα κάθε μέρα φτιάχνουν έναν άλλο άνθρωπο.", nil},
    {"Δεν χρειάζεται να είσαι σπουδαίος για να ξεκινήσεις, χρειάζεται να ξεκινήσεις για να γίνεις σπουδαίος.",
     "Zig Ziglar"},
    {"Το κίνητρο σε ξεκινά. Η συνήθεια σε κρατά.", "Jim Ryun"},
    {"Ξεκουράσου αν πρέπει, αλλά μην τα παρατάς.", nil},
    {"Πρόσεχε το σώμα σου. Είναι το μόνο μέρος που έχεις για να ζεις.", "Jim Rohn"},
    {"Σε έναν χρόνο θα εύχεσαι να είχες ξεκινήσει σήμερα.", "Karen Lamb"},
    {"Κάνε σήμερα κάτι που το μελλοντικό σου εγώ θα σε ευχαριστήσει.", nil},
    {"Οι τελευταίες επαναλήψεις είναι εκείνες που μεγαλώνουν τον μυ.", "Arnold Schwarzenegger"},
    {"Η σκληρή δουλειά νικά το ταλέντο όταν το ταλέντο δεν δουλεύει σκληρά.", "Tim Notke"},
    {"Είτε πιστεύεις ότι μπορείς είτε ότι δεν μπορείς, έχεις δίκιο.", "Henry Ford"},
    {"Πάντα φαίνεται αδύνατο, μέχρι να γίνει.", "Νέλσον Μαντέλα"},
    {"Όσο πιο σκληρή η μάχη, τόσο πιο γλυκιά η νίκη.", "Les Brown"},
    {"Η επιτυχία είναι το άθροισμα μικρών προσπαθειών που επαναλαμβάνονται κάθε μέρα.",
     "Robert Collier"},
    {"Όλα όσα ήθελες βρίσκονται στην άλλη πλευρά του φόβου.", "George Addair"},
    {"Η ενέργεια και η επιμονή κατακτούν τα πάντα.", "Βενιαμίν Φραγκλίνος"},
    {"Το σώμα πετυχαίνει ό,τι πιστεύει το μυαλό.", nil},
    {"Γίνε πιο δυνατός από τις δικαιολογίες σου.", nil},
    {"Είσαι μία προπόνηση μακριά από μια καλή διάθεση.", nil},
    {"Οι δυνατοί άνθρωποι δεν γεννιούνται, χτίζονται επανάληψη την επανάληψη.", nil},
    {"Κάθε προπόνηση που ολοκληρώνεις είναι μια υπόσχεση που κράτησες στον εαυτό σου.", nil},
    {"Η μέρα δεν τελείωσε μέχρι να κινηθείς.", nil},
    {"Έλα όπως είσαι. Φύγε πιο δυνατός.", nil}
  ]

  def up do
    alter table(:training_quotes) do
      add :locale, :string, null: false, default: "en"
    end

    create index(:training_quotes, [:locale])

    execute(
      "DELETE FROM training_quotes WHERE body IN (#{Enum.map_join(@retired, ", ", &literal/1)})"
    )

    insert("en", @en)
    insert("el", @el)
  end

  def down do
    execute("DELETE FROM training_quotes WHERE locale = 'el'")
    drop index(:training_quotes, [:locale])

    alter table(:training_quotes) do
      remove :locale
    end
  end

  defp insert(locale, quotes) do
    Enum.each(quotes, fn {body, author} ->
      execute("""
      INSERT INTO training_quotes (id, body, author, locale, inserted_at, updated_at)
      SELECT gen_random_uuid(), #{literal(body)}, #{literal(author)}, '#{locale}', now(), now()
      WHERE NOT EXISTS (SELECT 1 FROM training_quotes WHERE body = #{literal(body)})
      """)
    end)
  end

  defp literal(nil), do: "NULL"
  defp literal(text), do: "'" <> String.replace(text, "'", "''") <> "'"
end
