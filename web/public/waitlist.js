const form = document.getElementById("waitlist-form");

if (form) {
  const usernameInput = document.getElementById("waitlist-username");
  const emailInput = document.getElementById("waitlist-email");
  const checkButton = document.getElementById("waitlist-check");
  const submitButton = document.getElementById("waitlist-submit");
  const emailStep = document.getElementById("waitlist-email-step");
  const status = document.getElementById("waitlist-status");
  const success = document.getElementById("waitlist-success");
  let checkedUsername = "";

  function message(value, error = false) {
    status.textContent = value;
    status.classList.toggle("is-error", error);
  }

  usernameInput.addEventListener("input", () => {
    checkedUsername = "";
    emailStep.hidden = true;
    checkButton.hidden = false;
    message("");
  });

  async function checkUsername() {
    const username = usernameInput.value.trim().toLowerCase();
    if (!/^[a-z0-9_]{3,30}$/.test(username)) {
      message("Use 3–30 letters, numbers, or underscores.", true);
      usernameInput.focus();
      return;
    }
    checkButton.disabled = true;
    message("Checking…");
    try {
      const response = await fetch(`/api/waitlist/availability?username=${encodeURIComponent(username)}`);
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Could not check right now.");
      if (!result.available) {
        message("That username isn't available. Try another.", true);
        return;
      }
      checkedUsername = username;
      usernameInput.value = username;
      emailStep.hidden = false;
      checkButton.hidden = true;
      message(`@${username} is available. Add your email to save it.`);
      emailInput.focus();
    } catch (error) {
      message(error.message || "Could not check right now.", true);
    } finally {
      checkButton.disabled = false;
    }
  }

  checkButton.addEventListener("click", checkUsername);
  usernameInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      if (!emailStep.hidden) emailInput.focus();
      else checkUsername();
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!checkedUsername || emailStep.hidden) return checkUsername();
    const email = emailInput.value.trim();
    if (!emailInput.checkValidity()) {
      message("Enter a valid email address.", true);
      emailInput.focus();
      return;
    }
    submitButton.disabled = true;
    message("Saving your spot…");
    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: checkedUsername, email, company: form.elements.company.value }),
      });
      const result = await response.json();
      if (result.status === "joined") {
        form.hidden = true;
        document.getElementById("waitlist-success-copy").textContent = `@${checkedUsername} is reserved for the email you entered. We'll contact you about launch.`;
        success.hidden = false;
        success.querySelector("h2").focus?.();
        return;
      }
      const messages = {
        username_taken: "That username was just taken. Please choose another.",
        already_taken: "That username or email is already on the waitlist.",
        invalid_username: "Use 3–30 letters, numbers, or underscores.",
        invalid_email: "Enter a valid email address.",
      };
      message(messages[result.status] || result.error || "Could not save your spot right now.", true);
      if (result.status === "username_taken") {
        checkedUsername = "";
        emailStep.hidden = true;
        checkButton.hidden = false;
      }
    } catch {
      message("Could not save your spot right now. Please try again.", true);
    } finally {
      submitButton.disabled = false;
    }
  });
}
