// @ts-check
/**
 * @file Defines the custom logic for patching in UI changes/behavior into the
 * base Devolutions Gateway Angular app.
 *
 * Defined as a JS file to remove the need to have a separate compilation step.
 * It is highly recommended that you work on this file from within VS Code so
 * that you can take advantage of the @ts-check directive and get some type-
 * checking still.
 *
 * Other notes about the weird ways this file is set up:
 * - A lot of the HTML selectors in this file will look nonstandard. This is
 *   because they are actually custom Angular components.
 * - It is strongly advised that you avoid template literals that use the
 *   placeholder syntax via the dollar sign. The Terraform file is treating this
 *   as a template file, and because it also uses a similar syntax, there's a
 *   risk that some values will trigger false positives. If a template literal
 *   must be used, be sure to use a double dollar sign to escape things.
 * - All the CSS should be written via custom style tags and the !important
 *   directive (as much as that is a bad idea most of the time). We do not
 *   control the Angular app, so we have to modify things from afar to ensure
 *   that as Angular's internal state changes, it doesn't modify its HTML nodes
 *   in a way that causes our custom styles to get wiped away.
 *
 * @typedef {Readonly<{ querySelector: string; value: string; }>} FormFieldEntry
 * @typedef {Readonly<Record<string, FormFieldEntry>>} FormFieldEntries
 */
(function () {
  /**
   * The hostname to use with Devolutions.
   */
  const HOSTNAME = "localhost";

  /**
   * How often to poll the screen for the main Devolutions form.
   */
  const POLL_INTERVAL_MS = 500;

  /**
   * How many times each poll retries before giving up and surfacing the
   * failure to the user. The Angular app can take upwards of 20 seconds to
   * render the form on a cold start, so these ceilings are deliberately
   * generous.
   */
  const MAX_FORM_POLLS = 240;
  const MAX_TOOLBAR_POLLS = 120;

  /**
   * Selectors for the Devolutions markup this script drives.
   *
   * Devolutions builds its UI on PrimeNG, whose component names and class
   * lists change between releases. Prefer structural hooks (element type,
   * input type, aria-label) over class names, which have already broken once:
   * `p-dropdown` became `p-select`, `session-toolbar` became
   * `floating-session-toolbar`, and the submit button lost the `p-element`
   * class. Where a selector list is used, the newest form comes first and
   * older forms are kept as fallbacks.
   */
  const selectors = {
    form: "web-client-form form",
    hostname: "p-autocomplete#hostname input",
    submitButton: 'button[type="submit"], p-button button',
    displayControl: "input#enableDisplayControl",
    sessionToolbar: "floating-session-toolbar, session-toolbar",
    closeSession: 'button[aria-label="Close session" i]',
  };

  /**
   * The fields in the Devolutions sign-in form that should be populated with
   * values from the Coder workspace.
   *
   * All properties should be defined as placeholder templates in the form
   * VALUE_NAME. The Coder module, when spun up, should then run some logic to
   * replace the template slots with actual values. The module JSON-escapes each
   * value before injecting it, so characters like backslashes and quotes stay
   * intact inside these string literals. These values should never change from
   * within JavaScript itself.
   *
   * @satisfies {FormFieldEntries}
   */
  const formFieldEntries = {
    /** @readonly */
    username: {
      /** @readonly */
      querySelector: "web-client-username-control input",

      /** @readonly */
      value: "${CODER_USERNAME}",
    },
    /** @readonly */
    password: {
      /** @readonly */
      querySelector: "web-client-password-control input",

      /** @readonly */
      value: "${CODER_PASSWORD}",
    },
  };

  /**
   * CSS variable that controls whether the sign-in form is visible. Declared
   * at this scope so that failure paths can reveal the form again.
   */
  const cssOpacityVariableName = "--coder-opacity-multiplier";

  /**
   * Makes the Devolutions sign-in form visible again.
   *
   * @returns {void}
   */
  function revealForm() {
    const rootNode = document.querySelector(":root");
    if (rootNode instanceof HTMLHtmlElement) {
      rootNode.style.setProperty(cssOpacityVariableName, "1");
    }
  }

  /**
   * Reveals the form and displays a banner explaining that auto-connect did
   * not work.
   *
   * Without this, a selector that stops matching leaves the user staring at a
   * form that silently does nothing, with the explanation buried in a console
   * they are unlikely to open.
   *
   * @param {string} reason
   * @returns {void}
   */
  function reportAutoConnectFailure(reason) {
    log(`Auto-connect failed: $${reason}`);
    revealForm();

    const bannerId = "coder-patch--auto-connect-failure";
    // biome-ignore lint/style/useTemplate: Have to skip interpolation for the main.tf interpolation
    if (document.querySelector("#" + bannerId)) {
      return;
    }

    const banner = document.createElement("div");
    banner.id = bannerId;
    banner.textContent =
      "Coder could not sign in to this session automatically. " +
      "The form below has been filled in, so you can connect manually.";
    banner.style.cssText = [
      "position: fixed",
      "top: 0",
      "left: 0",
      "right: 0",
      "z-index: 9999",
      "padding: 12px 16px",
      "background: #fde68a",
      "color: #1f2937",
      "font-family: sans-serif",
      "text-align: center",
    ].join(";");

    document.body.appendChild(banner);
  }

  /**
   * This ensures that the Devolutions login form (which by default, always shows
   * up on screen when the app first launches) stays visually hidden from the user
   * when they open Devolutions via the Coder module.
   *
   * The form will still be filled out automatically and submitted in the
   * background via the rest of the logic in this file, so this function is mainly
   * to help avoid screen flickering and make the overall experience feel a little
   * more polished (even though it's just one giant hack).
   *
   * @returns {void}
   */
  function hideFormForInitialSubmission() {
    const styleId = "coder-patch--styles-initial-submission";

    /** @type {HTMLStyleElement | null} */
    // biome-ignore lint/style/useTemplate: Have to skip interpolation for the main.tf interpolation
    let styleContainer = document.querySelector("#" + styleId);
    if (!styleContainer) {
      styleContainer = document.createElement("style");
      styleContainer.id = styleId;
      styleContainer.innerHTML = `
        /*
          Have to use opacity instead of visibility, because the element still
          needs to be interactive via the script so that it can be auto-filled.
        */
        :root {
          /*
            Can be 0 or 1. Start off invisible to avoid risks of UI flickering,
            but the rest of the function should be in charge of making the form
            container visible again if something goes wrong during setup.

            Double dollar sign needed to avoid Terraform script false positives
          */
          $${cssOpacityVariableName}: 0;
        }

        /*
          web-client-form is the container for the main session form, while
          the div is for the dropdown that is used for selecting the protocol.
          The dropdown is not inside of the form for CSS styling reasons, so we
          need to select both.
        */
        web-client-form,
        body > div.p-overlay {
          /*
            Double dollar sign needed to avoid Terraform script false positives
          */
          opacity: calc(100% * var($${cssOpacityVariableName})) !important;
        }
      `;

      document.head.appendChild(styleContainer);
    }

    // The root node being undefined should be physically impossible (if it's
    // undefined, the browser itself is busted), but we need to do a type check
    // here so that the rest of the function doesn't need to do type checks over
    // and over.
    const rootNode = document.querySelector(":root");
    if (!(rootNode instanceof HTMLHtmlElement)) {
      // Remove the container entirely because if the browser is busted, who knows
      // if the CSS variables can be applied correctly. Better to have something
      // be a bit more ugly/painful to use, than have it be impossible to use
      styleContainer.remove();
      return;
    }

    // It's safe to make the form visible preemptively because Devolutions
    // outputs the Windows view through an HTML canvas that it overlays on top
    // of the rest of the app. Even if the form isn't hidden at the style level,
    // it will still be covered up.
    const restoreOpacity = () => {
      revealForm();
    };

    // If this file gets more complicated, it might make sense to set up the
    // timeout and event listener so that if one triggers, it cancels the other,
    // but having restoreOpacity run more than once is a no-op for right now.
    // Not a big deal if these don't get cleaned up.

    // Have the form automatically reappear no matter what, so that if something
    // does break, the user isn't left out to dry
    window.setTimeout(restoreOpacity, 5_000);

    /** @type {HTMLFormElement | null} */
    const form = document.querySelector("web-client-form > form");
    form?.addEventListener(
      "submit",
      () => {
        // Not restoring opacity right away just to give the HTML canvas a little
        // bit of time to get spun up and cover up the main form
        window.setTimeout(restoreOpacity, 1_000);
      },
      { once: true },
    );
  }

  /**
   * Sets up custom styles for hiding default Devolutions elements that Coder
   * users shouldn't need to care about.
   *
   * @returns {void}
   */
  function setupAlwaysOnStyles() {
    const styleId = "coder-patch--styles-always-on";
    // biome-ignore lint/style/useTemplate: Have to skip interpolation for the main.tf interpolation
    const existingContainer = document.querySelector("#" + styleId);
    if (existingContainer) {
      return;
    }

    const styleContainer = document.createElement("style");
    styleContainer.id = styleId;
    styleContainer.innerHTML = `
      /* app-menu corresponds to the sidebar of the default view. */
      app-menu {
        display: none !important;
      }

      /* app-net-scan corresponds to the auto-discovery feature. */
      app-net-scan {
        display: none !important;
      }
    `;

    document.head.appendChild(styleContainer);
  }

  /**
   * Handles typing in the values for the input form. All values are written
   * immediately, even though that would be physically impossible with a real
   * keyboard.
   *
   * Note: this code will never break, but you might get warnings in the console
   * from Angular about unexpected value changes. Angular patches over a lot of
   * the built-in browser APIs to support its component change detection system.
   * As part of that, it has validations for checking whether an input it
   * previously had control over changed without it doing anything.
   *
   * But the only way to simulate a keyboard input is by setting the input's
   * .value property, and then firing an input event. So basically, the inner
   * value will change, which Angular won't be happy about, but then the input
   * event will fire and sync everything back together.
   *
   * @param {HTMLInputElement} inputField
   * @param {string} inputText
   * @returns {Promise<void>}
   */
  function setInputValue(inputField, inputText) {
    return new Promise((resolve, reject) => {
      // Adding timeout for input event, even though we'll be dispatching it
      // immediately, just in the off chance that something in the Angular app
      // intercepts it or stops it from propagating properly
      const timeoutId = window.setTimeout(() => {
        reject(
          new Error("Input event did not get processed correctly in time."),
        );
      }, 3_000);

      const handleSuccessfulDispatch = () => {
        window.clearTimeout(timeoutId);
        inputField.removeEventListener("input", handleSuccessfulDispatch);
        resolve();
      };

      inputField.addEventListener("input", handleSuccessfulDispatch);

      // Code assumes that Angular will have an event handler in place to handle
      // the new event
      const inputEvent = new Event("input", {
        bubbles: true,
        cancelable: true,
      });

      inputField.value = inputText;
      inputField.dispatchEvent(inputEvent);
    });
  }

  /**
   * Takes a Devolutions remote session form, auto-fills it with data, and then
   * submits it.
   *
   * The logic here is more convoluted than it should be for two main reasons:
   * 1. Devolutions' HTML markup has errors. There are labels, but they aren't
   *    bound to the inputs they're supposed to describe. This means no easy hooks
   *    for selecting the elements, unfortunately.
   * 2. Trying to modify the .value properties on some of the inputs doesn't
   *    work. Probably some combo of Angular data-binding and some inputs having
   *    the readonly attribute. Have to simulate user input to get around this.
   *
   * @param {HTMLFormElement} form
   */
  async function fillForm(form) {
    try {
      log("Form detected. Starting auto-fill...");

      // The protocol control defaults to RDP, so this script does not touch
      // it. Selecting it explicitly meant driving a PrimeNG overlay, which is
      // exactly the kind of markup that changes between Gateway releases.

      const hostnameInput = form.querySelector(selectors.hostname);
      if (hostnameInput) {
        await setInputValue(hostnameInput, HOSTNAME);
        log(`Hostname set to $${HOSTNAME}`);
      } else {
        log("Hostname input not found.");
      }

      for (const [key, { querySelector, value }] of Object.entries(
        formFieldEntries,
      )) {
        const input = document.querySelector(querySelector);
        if (input) {
          await setInputValue(input, value);
          log(`Set $${key}`);
        } else {
          log(`Input for $${key} not found with selector: $${querySelector}`);
        }
      }

      // Resizes the remote display to match the browser window. Enabled by
      // default on current Gateway versions, so this only has to correct it
      // when it is not.
      const displayControl = document.querySelector(selectors.displayControl);
      if (displayControl && !displayControl.checked) {
        displayControl.click();
        log("Enabled display control.");
      }

      const submitButton = form.querySelector(selectors.submitButton);
      if (submitButton && !submitButton.disabled) {
        submitButton.click();
        log("Form submitted.");
      } else {
        reportAutoConnectFailure("submit button not found or disabled");
      }
    } catch (err) {
      console.error("[Devolutions Patch] Error during form fill:", err);
      reportAutoConnectFailure("unexpected error while filling the form");
    }
  }

  /**
   * Attaches a click event listener to the "Close Session" button within the provided top bar element.
   * When clicked, the listener triggers the window to close.
   * Logs a message indicating whether the listener was successfully attached or if the button was not found.
   *
   * @param {HTMLElement} topBar - The container element that includes the "Close Session" button.
   * @returns {void}
   */
  function attachCloseListener(topBar) {
    const closeButton = topBar.querySelector(selectors.closeSession);

    if (closeButton) {
      closeButton.addEventListener("click", () => {
        window.close();
      });
      log("Close listener attached.");
    } else {
      log("Close button not found in top bar.");
    }
  }

  /**
   * Continuously polls the DOM for the sign-in form, up to MAX_FORM_POLLS
   * attempts.
   * - Searches for a <form> inside a <web-client-form> element.
   * - If found, calls `fillForm(form)` to process it.
   * - If the ceiling is reached, surfaces the failure to the user.
   *
   * @param {number} [attempt]
   * @returns {void}
   */
  function pollForForm(attempt = 0) {
    const form = document.querySelector(selectors.form);
    if (form) {
      fillForm(form);

      // Start polling for top bar after form is filled
      pollForSessionToolBar();
      return;
    }

    if (attempt >= MAX_FORM_POLLS) {
      reportAutoConnectFailure("sign-in form never appeared");
      return;
    }

    log("Form not yet available. Retrying...");
    setTimeout(() => pollForForm(attempt + 1), POLL_INTERVAL_MS);
  }

  /**
   * Continuously polls the DOM for the in-session toolbar, up to
   * MAX_TOOLBAR_POLLS attempts.
   * - Searches for the floating session toolbar element.
   * - If found, attaches the close listener.
   * - If the ceiling is reached, stops polling and logs.
   *
   * @param {number} [attempt]
   * @returns {void}
   */
  function pollForSessionToolBar(attempt = 0) {
    const sessionToolBar = document.querySelector(selectors.sessionToolbar);
    if (sessionToolBar) {
      log("Top bar detected. Proceeding with next steps...");
      attachCloseListener(sessionToolBar);
      return;
    }

    if (attempt >= MAX_TOOLBAR_POLLS) {
      log("Top bar never appeared. Stopped polling.");
      return;
    }

    log("Top bar not yet available. Retrying...");
    setTimeout(() => pollForSessionToolBar(attempt + 1), POLL_INTERVAL_MS);
  }

  /**
   * Logs a message to the console with a standardized prefix.
   * Format: [Devolutions Patch] $<message>
   *
   * @param {string} msg - The message to log.
   * @returns {void}
   */
  function log(msg) {
    console.log(`[Devolutions Patch] $${msg}`);
  }

  // Always safe to call these immediately because even if the Angular app isn't
  // loaded by the time the function gets called, the CSS will always be globally
  // available for when Angular is finally ready
  setupAlwaysOnStyles();
  hideFormForInitialSubmission();

  log("Script loaded. Starting form detection...");
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", pollForForm);
  } else {
    pollForForm();
  }
})();
