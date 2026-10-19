import { Email, LegalPage } from './LegalPage'

/*
 * Google Play's "Delete account URL": how to delete a Hawk account without the
 * app, what goes and what stays. Written from what `delete_account`
 * (firebase/functions/account_api.py) and the app's Profile tab actually do;
 * change it with them.
 */
export function DeleteAccountPage() {
  return (
    <LegalPage
      title="Delete your Hawk account"
      updated="27 September 2026"
      summary={
        <ul>
          <li>
            <strong>In the app:</strong> go to the Profile tab, tap Delete account and type DELETE. It happens
            straight away.
          </li>
          <li>
            <strong>Without the app:</strong> email <Email /> from your account’s email address. Your account is
            deleted within 30 days, and you’ll get a reply when it’s done.
          </li>
          <li>
            <strong>Everything Hawk holds about you is deleted.</strong> Files in your Google Drive and on your phone
            are not touched.
          </li>
          <li>
            <strong>Cancel your subscription separately,</strong> in Google Play or the App Store. Deleting your
            account doesn’t stop the store from billing you.
          </li>
        </ul>
      }
    >
      <h2>Delete it in the app</h2>
      <ol>
        <li>Open Hawk and go to the Profile tab.</li>
        <li>Tap Delete account.</li>
        <li>Type DELETE to confirm.</li>
      </ol>
      <p>
        Your account is deleted at once, and this can’t be undone. If you only want a break, Deactivate on the same
        screen disconnects your storage and stops indexing but keeps your memories; signing in again brings it all
        back.
      </p>

      <h2>Ask by email, without the app</h2>
      <p>
        If you no longer have the app, email <Email /> with the subject “Delete my Hawk account”, from the email
        address you sign in to Hawk with. If you sign in with Google or Apple, that’s the address of that account. If
        you can’t write from that address, tell us which address your account uses, and Hawk will confirm the account
        is yours before deleting anything.
      </p>
      <p>Your account is deleted within 30 days of your request, and you’ll get a reply when it’s done.</p>

      <h2>What is deleted</h2>
      <ul>
        <li>
          <strong>Your account:</strong> your sign-in record and your profile.
        </li>
        <li>
          <strong>Your memories:</strong> everything you captured, the text Hawk read from it, and the files kept
          in your Hawk account.
        </li>
        <li>
          <strong>Your conversations:</strong> the questions you asked and Hawk’s answers.
        </li>
        <li>
          <strong>Your connections:</strong> Hawk’s access to your Google Drive is revoked, and the keys for it are
          deleted.
        </li>
        <li>
          <strong>Your plan and usage records</strong> held by Hawk.
        </li>
        <li>
          <strong>The search index on your phone</strong> is removed when you sign out of Hawk or uninstall it.
        </li>
      </ul>

      <h2>What is kept</h2>
      <ul>
        <li>
          <strong>Your own files.</strong> Files in your Google Drive and the originals on your phone are never
          deleted by Hawk. They are yours.
        </li>
        <li>
          <strong>Store purchase records</strong>, which Google Play and the App Store keep under their own
          policies. To stop a subscription, cancel it in Google Play (Payments &amp; subscriptions) or on your iPhone
          (Settings, then your name, then Subscriptions).
        </li>
        <li>
          <strong>Server logs</strong>, which record technical events rather than your content, expire within 30
          days.
        </li>
      </ul>
      <p>Apart from these, Hawk keeps no copy of your data once your account is deleted.</p>

      <h2>Delete some data, keep your account</h2>
      <ul>
        <li>
          <strong>A memory:</strong> delete it in the app. Its file and text go straight away. An empty record,
          with none of the content, stays for up to 30 days so your other devices learn it was deleted, then it is
          removed too.
        </li>
        <li>
          <strong>Google Drive:</strong> disconnect it in the app, or remove Hawk’s access in your Google Account
          settings.
        </li>
        <li>
          <strong>Anything else:</strong> email <Email /> and say what you’d like deleted.
        </li>
      </ul>
      <p>
        The <a href="/privacy">Privacy Policy</a> explains everything Hawk collects and why.
      </p>
    </LegalPage>
  )
}
