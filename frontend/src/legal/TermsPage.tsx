import { Email, LegalPage } from './LegalPage'

export function TermsPage() {
  return (
    <LegalPage
      title="Terms of Service"
      updated="27 September 2026"
      summary={
        <ul>
          <li>
            <strong>Your content stays yours.</strong> Hawk only uses it to run the service for you.
          </li>
          <li>
            <strong>Answers can be wrong.</strong> Hawk writes them from your own files; check the file it points to
            before you rely on one.
          </li>
          <li>
            <strong>Keep your own copies.</strong> Hawk helps you find things. It is not a backup.
          </li>
          <li>
            <strong>You can leave at any time</strong> by deleting your account in the app.
          </li>
        </ul>
      }
    >
      <p>
        These terms apply when you use the Hawk app or this website. By using Hawk, you agree to them. The{' '}
        <a href="/privacy">Privacy Policy</a> explains how your data is handled, and is part of these terms.
      </p>

      <h2>Using Hawk</h2>
      <ul>
        <li>
          Hawk is for all ages. If you are under 13, or under the age at which the law where you live lets you agree
          to terms like these yourself, a parent or guardian must agree to them for you, and help you use Hawk.
        </li>
        <li>Keep your sign-in secure. You are responsible for what happens in your account.</li>
        <li>Only use Hawk for your own content, or content you have the right to use.</li>
      </ul>

      <h2>Your content</h2>
      <p>
        Everything you capture or connect remains yours. You give Hawk permission to store, read, index and process
        it, including through the services named in the Privacy Policy, only so that Hawk can work for you: finding
        your things, answering your questions, and showing your files back to you. That permission ends when you
        delete the content or your account.
      </p>

      <h2>Acceptable use</h2>
      <p>Don’t use Hawk to:</p>
      <ul>
        <li>store or share anything illegal, or anything that infringes someone else’s rights;</li>
        <li>get into anyone else’s account or data;</li>
        <li>attack, overload, probe or reverse-engineer the service, or get round its limits;</li>
        <li>use saved links to reach systems you are not allowed to reach.</li>
      </ul>

      <h2>Answers are generated, and can be wrong</h2>
      <p>
        Hawk’s answers are written by AI from your own content. They can be incomplete or mistaken, so check the
        file an answer points to before you rely on it, especially for anything important such as health, money or
        legal matters.
      </p>

      <h2>Not a backup</h2>
      <p>
        Files in your Google Drive stay in your Drive, and Hawk does not change them unless you turn on file
        management yourself. Hawk keeps what you capture in the app, up to your plan’s storage allowance (beyond it,
        the original stays only on your phone), but it is not a backup service: keep your own copies of anything you
        can’t afford to lose.
      </p>

      <h2>Plans and payments</h2>
      <p>
        Hawk has a free plan and paid plans. They differ in how many answers Hawk writes for you (counted over a
        rolling two hours and per week, and only answers drawn from your files count), how many accounts you can
        connect, how much Hawk keeps for you, and how long memories stay searchable. On the free plan a memory stops
        appearing in search and answers 30 days after you capture it; it stays in your library, and upgrading brings
        it back. Searching your own files is never limited. Paid subscriptions are bought through the App Store or Google Play.
        Billing, renewal, cancellation and refunds are handled by that store, under its terms. Plans and prices may
        change; a change to a paid plan applies from your next billing period, not the one you have already paid
        for.
      </p>

      <h2>Other services</h2>
      <p>
        Google Drive, sign-in with Google or Apple, and the app stores are provided by other companies. When you use
        them through Hawk, their own terms apply as well.
      </p>

      <h2>Changes to Hawk</h2>
      <p>
        Hawk is new and will change. Features may be added, changed or removed, and the service may sometimes be
        unavailable.
      </p>

      <h2>Ending</h2>
      <p>
        You can pause or delete your account in the app at any time. Hawk may suspend or close an account that
        breaks these terms, and will tell you why unless the law prevents it.
      </p>

      <h2>Disclaimer and liability</h2>
      <p>
        Hawk is provided “as is”, without warranties of any kind, to the extent the law allows. To the extent the
        law allows, Hawk is not liable for indirect or consequential losses, or for lost data or lost profits, and
        its total liability for any claim is limited to what you paid for Hawk in the 12 months before the claim.
        Nothing in these terms limits rights you have under the law that cannot be limited.
      </p>

      <h2>Changes to these terms</h2>
      <p>
        When these terms change, the date at the top changes with them. If a change matters, you’ll be told in the
        app before it takes effect. Using Hawk after that means you accept the new terms.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about these terms: <Email />.
      </p>
    </LegalPage>
  )
}
