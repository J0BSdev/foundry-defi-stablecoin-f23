# DSCEngine – Vodič za učenje

Ovaj dokument objašnjava kako funkcionira decentralizirani stablecoin sustav – DSCEngine, kolateral, health factor, likvidacija i testovi.

---

## 1. Velika slika: Što je ovaj sustav?

```
┌─────────────────────────────────────────────────────────────────┐
│                    DECENTRALIZIRANI STABLECOIN                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Korisnik deponira kolateral (WETH, WBTC)  ──►  Engine          │
│                          │                                        │
│                          ▼                                        │
│   Korisnik može mintati DSC (1 DSC ≈ 1 USD)  ◄──  Engine         │
│                          │                                        │
│                          ▼                                        │
│   Ako cijena kolaterala padne → Likvidacija (netko drugi         │
│   pokriva tvoj dug i dobiva tvoj kolateral + bonus)               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Ključna ideja:** DSC nije backed 1:1 kolateralom. Sustav je **over-collateralized** – moraš deponirati više vrijednosti kolaterala nego koliko DSC mintiraš.

---

## 2. Glavni ugovori

| Ugovor | Uloga |
|--------|--------|
| **DecentralizedStableCoin (DSC)** | ERC20 token. Engine ga može mintati i burnati. Korisnici ga drže kao “dug”. |
| **DSCEngine** | Motor sustava. Upravlja kolateralom, mintanjem, burnanjem i likvidacijom. |
| **Chainlink / MockV3Aggregator** | Oracles za cijene kolaterala u USD. |

---

## 3. Konstante u DSCEngine – što znače

```solidity
LIQUIDATION_THRESHOLD = 50    // 50% – kolateral se računa na 50% vrijednosti
LIQUIDATION_BONUS = 10        // 10% – liquidator dobiva 10% popusta
LIQUIDATION_PRECISION = 100   // za računanje postotaka
MIN_HEALTH_FACTOR = 1e18     // HF mora biti >= 1
PRECISION = 1e18             // precision za matematiku
ADDITIONAL_FEED_PRECISION = 1e10  // Chainlink feed ima 8 decimals
FEED_PRECISION = 1e8         // Chainlink standard
```

**Zašto 50%?**  
Ako imaš $20,000 kolaterala, sustav ti dopušta max $10,000 DSC. To znači da trebaš biti barem 200% over-collateralized (dvostruko više kolaterala nego duga).

---

## 4. Health Factor – srce sustava

### Formula

```
Health Factor = (collateralValueInUSD × 50%) / totalDscMinted
```

U kodu:
```solidity
collateralAdjustedForThreshold = collateralValueInUSD * 50 / 100
healthFactor = (collateralAdjustedForThreshold * 1e18) / totalDscMinted
```

### Pravila

- **HF ≥ 1** → pozicija je OK, ne može se likvidirati
- **HF < 1** → pozicija je underwater, može se likvidirati

### Primjer

- Kolateral: 10 ETH × $2000 = **$20,000**
- Max DSC (50% od $20,000) = **$10,000**
- Ako mintiraš $5,000 DSC: HF = $10,000 / $5,000 = **2** ✓
- Ako mintiraš $10,101 DSC: HF = $10,000 / $10,101 = **0.99** ✗ → revert

---

## 5. Storage – gdje se sve čuva

```solidity
// token -> Chainlink price feed adresa
mapping(address token => address priceFeed) s_priceFeeds;

// user -> (token -> koliko je deponirao)
mapping(address user => mapping(address token => uint256 amount)) s_collateralDeposited;

// user -> koliko je mintao DSC (dug)
mapping(address user => uint256 amountDscMinted) s_DscMinted;

// lista svih dozvoljenih tokena
address[] s_collateralTokens;
```

---

## 6. Funkcije – redoslijed i logika

### 6.1 `depositCollateral(token, amount)`

1. Provjera: `amount > 0`, token je dozvoljen
2. Povećava `s_collateralDeposited[msg.sender][token]`
3. Prenosi tokene od usera u Engine (`transferFrom`)
4. Emitira `CollateralDeposited`

**Napomena:** Ne provjerava HF jer deposit samo povećava kolateral i poboljšava poziciju.

---

### 6.2 `mintDsc(amount)`

1. Provjera: `amount > 0`
2. Povećava `s_DscMinted[msg.sender]`
3. Provjera HF (mora biti ≥ 1)
4. `i_dsc.mint(msg.sender, amount)` – kreira DSC tokene

**Napomena:** Moraš imati dovoljno kolaterala prije mintanja.

---

### 6.3 `depositCollateralAndMintDsc(token, amountCollateral, amountDsc)`

Samo convenience – poziva `depositCollateral` pa `mintDsc` u jednom pozivu.

---

### 6.4 `burnDsc(amount)`

1. Provjera: `amount > 0`
2. Smanjuje `s_DscMinted[msg.sender]`
3. Uzima DSC od usera (`transferFrom`) i burna ga
4. Provjera HF (nakon burna pozicija mora ostati OK)

**Napomena:** Moraš `approve` Engine prije burnanja.

---

### 6.5 `redeemCollateral(token, amount)`

1. Provjera: `amount > 0`, token dozvoljen
2. Smanjuje `s_collateralDeposited[msg.sender][token]`
3. Šalje tokene natrag useru
4. Provjera HF – ne smiješ povući toliko kolaterala da HF padne ispod 1

---

### 6.6 `redeemCollateralForDsc(token, amountCollateral, amountDscToBurn)`

Atomska operacija:
1. Burna `amountDscToBurn` DSC
2. Redeema `amountCollateral` kolaterala
3. Provjera HF

Korisno kad želiš istovremeno smanjiti dug i povući kolateral.

---

### 6.7 `liquidate(collateral, user, debtToCover)`

**Tko može pozvati:** Bilo tko (liquidator)

**Uvjeti:**
- `user` mora imati HF < 1 (underwater)
- Liquidator mora imati DSC da pokrije `debtToCover`

**Što se događa:**
1. Računa koliko kolaterala vrijedi `debtToCover` u USD
2. Dodaje 10% bonus (liquidator kupuje jeftinije)
3. Uzima kolateral od `user` i daje ga liquidatoru
4. Uzima DSC od liquidatora i burna ga (smanjuje dug `user`-a)
5. Provjera: HF usera se mora poboljšati, HF liquidatora mora biti OK

**Primjer:**
- User ima 10 ETH i dug 100 DSC. Cijena ETH padne na $18.
- Kolateral = $180, max DSC = $90 → HF < 1.
- Liquidator šalje 100 DSC engineu, engine burna 100 DSC userovog duga.
- Liquidator dobiva kolateral vrijedan $100 + 10% = ekvivalent ~$110 u kolateralu.

---

## 7. Pomoćne funkcije (view)

| Funkcija | Što radi |
|----------|----------|
| `getUsdValue(token, amount)` | Pretvara amount tokena u USD (Chainlink cijena) |
| `getTokenAmountFromUsd(token, usdAmount)` | Obrnuto – koliko tokena za X USD |
| `getAccountCollateralValue(user)` | Zbroj vrijednosti svih kolaterala usera u USD |
| `getAccountInformation(user)` | `(totalDscMinted, collateralValueInUSD)` |

---

## 8. Matematika preciznosti

Chainlink feed vraća cijenu s 8 decimals (npr. $2000 = 2000e8).

### USD vrijednost kolaterala
```
usdValue = (price * 1e10) * amount / 1e18
```
`1e10` kompenzira 8 decimals feeda; `amount` je obično u 18 decimals (wei).

### Token amount iz USD
```
tokenAmount = (usdAmountInWei * 1e18) / (price * 1e10)
```

---

## 9. Testovi – što svaki provjerava

### Constructor i setup
- `testRevertsIfTokenLenghtDoesntMatchPriceFeed` – broj tokena mora odgovarati broju feedova

### Cijene i konverzije
- `testGetTokenAmountFromUsd` – USD → token
- `testGetUSdValue` – token → USD

### Deposit
- `testRevertsIfCollateralZero` – 0 amount reverta
- `testRevertsWithUnapprovedCollateral` – nedozvoljeni token reverta
- `testCanDepositCollateralWithoutMinting` – deposit bez mintanja
- `testCanDepositCollateralAndGetAcountInfo` – account info nakon deposita

### Mint
- `testRevertsIfMintedDscIsZero` – 0 mint reverta
- `testRevertIfNotEnoughCollateral` – mint bez kolaterala reverta
- `testMintDsc` – uspješan mint
- `testRevertIfHealthFactorIsBroken` – mint preko limita reverta
- `testHealthFactorIsOkAfterMint` – HF je točan nakon mintanja

### Burn
- `testBurnDsc` – uspješan burn
- `testRevertIfYouTryToBurnMoreThanYouHave` – burn više nego imaš reverta

### Redeem
- `testRevertIfAmountIsZero` – 0 redeem reverta
- `testRedeemCollateral` – uspješan redeem
- `testRevertIfHealthFactorIsUnderMin` – redeem koji sruši HF reverta
- `testRedeemCollateralForDsc` – atomski redeem + burn

### Likvidacija
- `testLiquidateRevertsIfHealthFactorOk` – ne možeš likvidirati kad je HF OK
- `testLiquidate` – puna likvidacija radi
- `testPartialLiquidation` – djelomična likvidacija (samo dio duga)

### Kombinacije
- `testDepositCollateralAndMintDsc` – convenience funkcija radi

---

## 10. Modifieri u testovima

```solidity
modifier depositedCollateral() {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(engine), amountCollateral);
    engine.depositCollateral(weth, amountCollateral);
    vm.stopPrank();
    _;
}

modifier depositedCollateralAndMintedDsc() {
    // deposit + mint
    _;
}
```

Koriste se da izbjegneš ponavljanje istog setup koda u svakom testu.

---

## 11. Kako učiti – preporučeni redoslijed

1. **Pročitaj** ovaj dokument od početka.
2. **Otvori** `DSCEngine.sol` i prati funkcije prema ovom vodiču.
3. **Pokreni** `forge test -vvv` i gledaj output.
4. **Prođi** test po test – za svaki pogledaj što se očekuje.
5. **Nacrtaj** flow na papir: deposit → mint → (cijena pada) → liquidate.
6. **Eksperimentiraj** – promijeni brojeve u testu i vidi što se događa.

---

## 12. Cheat sheet – brzi pregled

| Akcija | Funkcija | Uvjeti |
|--------|----------|--------|
| Deponirati kolateral | `depositCollateral` | approve, amount > 0, dozvoljen token |
| Mintati DSC | `mintDsc` | Dovoljno kolaterala, HF ≥ 1 |
| Burnati DSC | `burnDsc` | approve, amount ≤ balance |
| Povući kolateral | `redeemCollateral` | HF ostaje ≥ 1 nakon |
| Likvidirati | `liquidate` | User HF < 1, liquidator ima DSC |

---

## 13. Korisni linkovi

- [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)
- [Over-collateralized stablecoins](https://docs.makerdao.com/)
- [Foundry Book](https://book.getfoundry.sh/) – testiranje

---

*Napravljeno kao vodič za učenje DSCEngine sustava.*
