const buttons = [...document.querySelectorAll("[data-preview]")];
const image = document.querySelector("#app-preview");
const language = document.documentElement.lang === "zh-CN" ? "zh-CN" : "en";
function selectPreview(button) {
  for (const item of buttons) {
    item.setAttribute("aria-selected", String(item === button));
    item.tabIndex = item === button ? 0 : -1;
  }
  const name = button.dataset.preview;
  image.src = `/assets/${name}.${language}-2400.webp`;
  image.srcset = `/assets/${name}.${language}-1280.webp 1280w, /assets/${name}.${language}-2400.webp 2400w`;
  image.alt = button.dataset.alt;
  document
    .querySelector("#preview-panel")
    .setAttribute("aria-labelledby", button.id);
}
for (const button of buttons) {
  button.addEventListener("click", () => selectPreview(button));
  button.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const index = buttons.indexOf(button);
    const next =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? buttons.length - 1
          : (index + (event.key === "ArrowRight" ? 1 : -1) + buttons.length) %
            buttons.length;
    buttons[next].focus();
    selectPreview(buttons[next]);
  });
}
