// On small screens, native <details> provides a keyboard-accessible menu.
// Desktop navigation stays open; no viewport width is cached across a resize.
const navigation = document.querySelector('.navigation');
const compact = window.matchMedia('(max-width: 1100px)');
function updateNavigation() {
    if (navigation) navigation.open = !compact.matches;
}
updateNavigation();
compact.addEventListener('change', updateNavigation);
