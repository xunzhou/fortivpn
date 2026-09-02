# Maintainer: fortivpn contributors
pkgname=fortivpn
pkgver=0.1.0
pkgrel=1
pkgdesc='Secure SAML launcher for OpenFortiVPN'
arch=('any')
license=('MIT')
depends=('bash' 'coreutils' 'sudo' 'procps-ng' 'openfortivpn' 'openfortivpn-webview-qt')
checkdepends=('bats')
source=('fortivpn'
        'fortivpn.bats'
        'LICENSE')

check() {
  FORTIVPN_UNDER_TEST="$srcdir/fortivpn" bats "$srcdir/fortivpn.bats"
}

package() {
  install -Dm755 "$srcdir/fortivpn" "$pkgdir/usr/bin/fortivpn"
  install -Dm644 "$srcdir/LICENSE" \
    "$pkgdir/usr/share/licenses/fortivpn/LICENSE"
}
sha256sums=('14d31cad01267bfe3951b783ec8cdd81453e157a73eaf2a551077eba2dddfee2'
            'de2f8095d7058e007f4a1f1547fee09f9541cb16b174cd7fd23def1355b2b6bf'
            '01ff054a60e7234eaf81c5b86e9264b58900dcdbf56e4398e134bd68faf1f685')
