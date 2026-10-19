import { Email, LegalPage } from './LegalPage'

/*
 * Written from what the app and its backend actually do (app/, firebase/
 * functions/), not from a template. When the data handling changes, change
 * this page in the same breath; the Gemini tier paragraph especially.
 */
export function PrivacyPage() {
  return (
    <LegalPage
      title="Privacy Policy"
      updated="27 September 2026"
      summary={
        <ul>
          <li>
            <strong>Files in your Google Drive stay in your Drive.</strong> Hawk reads them to make them searchable.
            It keeps the text it reads and a pointer back to each file, not a copy.
          </li>
          <li>
            <strong>Search happens on your phone.</strong> The index that makes your memories searchable is kept only
            on your device, and signing out removes it.
          </li>
          <li>
            <strong>What you capture in the app</strong> (photos, scans, voice notes, files, links) is kept in your
            Hawk account, so you can open it again on any device.
          </li>
          <li>
            <strong>No ads, no selling.</strong> Hawk doesn’t sell your data or use it for advertising. The app runs
            no analytics, and this website only counts visits if you allow it.
          </li>
          <li>
            <strong>You can delete it all.</strong> Delete a single memory, or your whole account, from inside the
            app.
          </li>
          <li>
            <strong>Families are welcome.</strong> Children can keep their memories in Hawk too, with a parent or
            guardian’s permission, and a parent can ask to see or delete a child’s data at any time.
          </li>
        </ul>
      }
    >
      <p>
        Hawk is an app that finds your own photos, documents, notes and voice notes when you ask for them in your
        own words. To do that it has to read what you give it. This policy explains what Hawk collects, what it does
        with it, which other companies process it, and how to delete it. It covers the Hawk app and this website.
      </p>

      <h2>What Hawk collects</h2>

      <h3>Your account</h3>
      <p>
        Your name and email address when you sign in with Google or Apple, or the email address you sign in with
        directly. For email sign-in, Hawk sends a six-digit code that expires after ten minutes.
      </p>

      <h3>What you capture</h3>
      <p>
        Notes, photos, scanned documents, files, voice recordings and links you save in the app. Files are kept in
        your Hawk account, up to your plan’s storage allowance. Beyond it, a new capture is still made searchable
        but Hawk doesn’t keep a copy of the file; the original stays on your phone. When you save a link, Hawk
        fetches that page to read its text.
      </p>

      <h3>Your Google Drive, if you connect it</h3>
      <p>
        Hawk asks for read-only access to your Drive, plus your Drive account’s email address. It reads the files in
        the folders you choose, and checks them for changes from time to time. From each file it keeps the text it
        extracted and a pointer back to the file. It does not keep a copy of the file itself. Hawk asks for wider
        access only if you turn on file management yourself.
      </p>

      <h3>Your search index, on your phone</h3>
      <p>
        To make your memories searchable, Hawk turns their text into a search index. Hawk’s servers work it out
        through the Gemini API and pass it straight to your phone without keeping it, and the index is stored only
        on your device, where searching happens. Signing out removes it from the phone.
      </p>

      <h3>Your questions</h3>
      <p>
        The questions you ask, typed or spoken, and Hawk’s answers, saved as conversations in your account. When you
        ask by voice, your phone’s built-in speech recognition (Apple’s on iPhone, Google’s on Android) turns your
        voice into text, and Hawk receives the text. That service may process the audio under Apple’s or Google’s own
        terms. Voice notes you record and save are kept like any other capture.
      </p>

      <h3>Your plan and usage</h3>
      <p>
        Your plan, how much storage you use, and what the answer limits need: the times of answers used in the last
        two hours, and a count for the current week.
        Subscriptions are bought through the App Store or Google Play. Hawk receives the status of your purchase,
        never your card details.
      </p>

      <h3>Crash reports</h3>
      <p>
        The app does not send crash reports today. If that changes, this policy will say so first. Reports would go
        to Sentry, carry only the error with your device model, operating system and app version (never your files
        or what’s in them), and could be turned off in the app’s privacy settings.
      </p>

      <h2>How Hawk uses it</h2>
      <ul>
        <li>To read your captures and connected files, and make them searchable.</li>
        <li>To answer your questions from your own content, and point to the file each answer came from.</li>
        <li>To show you your files again, on any device you sign in on.</li>
        <li>To keep connected folders up to date, and to apply your plan’s limits.</li>
        <li>To send sign-in codes.</li>
      </ul>
      <p>That is all. Hawk doesn’t sell your data, share it with advertisers, or build an advertising profile of you.</p>

      <h2>Who else processes your data</h2>
      <p>Hawk runs on a few services that process data for it:</p>
      <ul>
        <li>
          <strong>Google Firebase</strong> (Google Cloud): your account, your database, stored files and the servers
          that run Hawk.
        </li>
        <li>
          <strong>Google Gemini API</strong>: text and files are sent to it to read them (for example, to describe a
          photo and any text in it, or to transcribe a recording), to build the search index, and to write answers
          from your content. Hawk uses Gemini as a paid
          service: under Google’s terms for paid use, Google doesn’t use what Hawk sends to improve its products, and
          keeps it only for a limited time to detect misuse and meet legal requirements.
        </li>
        <li>
          <strong>Google Drive</strong>, if you connect it, and <strong>Google or Apple</strong> if you sign in with
          them.
        </li>
        <li>
          <strong>An email delivery service</strong>, to send your sign-in codes.
        </li>
        <li>
          <strong>The App Store and Google Play</strong>, for subscriptions.
        </li>
        <li>
          <strong>Vercel</strong>, which hosts this website.
        </li>
        <li>
          <strong>Google Analytics</strong>, on this website only, and only if you allow it.
        </li>
      </ul>
      <p>
        Hawk may also disclose information if the law requires it, for example to comply with a valid legal
        request.
      </p>

      <h2 id="google-user-data">Data from Google</h2>
      <p>
        Hawk’s use and transfer to any other app of information received from Google APIs, including your Google
        Drive, will adhere to the{' '}
        <a href="https://developers.google.com/terms/api-services-user-data-policy">
          Google API Services User Data Policy
        </a>
        , including the Limited Use requirements. Hawk uses that data only to find your files and answer your
        questions, and never uses it to develop, improve or train general-purpose AI or machine-learning models.
      </p>

      <h2>How it is kept safe</h2>
      <p>
        Everything travels encrypted. Each account’s data can only be read by that account. The keys that let Hawk
        read your Drive are stored encrypted, and are revoked when you delete your account. No system is perfectly
        secure, but these protections are built into how Hawk stores data.
      </p>

      <h2>Keeping and deleting your data</h2>
      <ul>
        <li>
          <strong>How long memories stay searchable</strong> depends on your plan. On the free plan, a memory stops
          appearing in search and answers 30 days after you capture it; it stays in your library and is not deleted.
          Standard keeps memories searchable for a year, Premium for as long as you keep them. Upgrading makes them
          searchable again straight away.
        </li>
        <li>
          <strong>Deleting a memory</strong> deletes its stored file and its text straight away. An empty record,
          with none of the content, stays for up to 30 days so your other devices learn it was deleted, then it is
          removed too.
        </li>
        <li>
          <strong>Signing out</strong> removes the search index from that phone.
        </li>
        <li>
          <strong>Pausing your account</strong> disconnects your storage and stops all indexing, but keeps your
          memories. Signing in again brings it back.
        </li>
        <li>
          <strong>Deleting your account</strong> removes everything: your memories and their text, your
          conversations, your stored files, your profile and your sign-in record, and revokes Hawk’s access to your
          Drive. Files in your Drive are not touched.{' '}
          <a href="/delete-account">How to delete your account</a>, with or without the app.
        </li>
        <li>
          You can disconnect Google Drive in the app at any time, or remove Hawk’s access from your Google Account
          settings.
        </li>
      </ul>
      <p>
        You can also ask by email for a copy of your data, a correction, or deletion. Depending on where you live,
        the law may give you further rights over your data; email <Email /> to use them.
      </p>

      <h2>Children</h2>
      <p>
        Hawk is for everyone, children included: for keeping memories, and for fun. A child under 13, or under the
        age at which the law where they live lets them agree to this policy themselves, should use Hawk with a parent
        or guardian’s permission, and the parent or guardian agrees to it on their behalf.
      </p>
      <p>
        Hawk collects nothing more from a child than from anyone else, never shows a child ads, and never builds a
        profile of them. A parent or guardian can ask to see, correct or delete a child’s data at any time by
        emailing <Email />.
      </p>

      <h2 id="this-website">This website</h2>
      <p>
        This website’s fonts are served from the site itself. Vercel, which hosts it, handles the usual details of
        each request (such as your IP address and browser) in order to deliver the site and protect it from abuse.
      </p>
      <p>
        If you allow it, the website also uses Google Analytics to count visits: which pages are viewed, roughly
        where from (country or city), on what kind of device and browser, which site sent you, and a few actions
        such as tapping Install or turning on the film’s sound. Its cookies (named <code>_ga</code>) are set only
        after you allow it; until then, or if you choose No thanks, nothing is loaded from Google. Google Analytics
        doesn’t store IP addresses, keeps this data for at most 14 months, and has Google signals and ad
        personalisation turned off for Hawk.
      </p>
      <p>
        You can change your choice at any time with <strong>Cookie settings</strong> at the bottom of any page;
        saying no also removes the cookies.
      </p>

      <h2>Changes to this policy</h2>
      <p>
        When this policy changes, the date at the top changes with it. If a change affects how your data is used,
        you’ll be told in the app before it takes effect.
      </p>

      <h2>Contact</h2>
      <p>
        Questions or requests about your data: <Email />.
      </p>
    </LegalPage>
  )
}
