/**
 * @param {HTMLFormElement} form
 * @returns {Promise<Response>}
 */
export async function fetchAutosaveForm(form) {
  if (!form?.action) return Promise.resolve(new Response(null, { status: 400 }))

  const fd = new FormData(form)
  fd.set("autosave", "1")
  const token =
    document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""

  return fetch(form.action, {
    method: "POST",
    body: fd,
    headers: {
      Accept: "application/json",
      "X-Requested-With": "XMLHttpRequest",
      ...(token ? { "X-CSRF-Token": token } : {})
    },
    credentials: "same-origin"
  })
}

/**
 * @param {string} url
 * @param {FormData} body
 * @returns {Promise<Response>}
 */
export async function fetchAutosavePost(url, body) {
  const token =
    document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  body.set("autosave", "1")

  return fetch(url, {
    method: "POST",
    body,
    headers: {
      Accept: "application/json",
      "X-Requested-With": "XMLHttpRequest",
      ...(token ? { "X-CSRF-Token": token } : {})
    },
    credentials: "same-origin"
  })
}
