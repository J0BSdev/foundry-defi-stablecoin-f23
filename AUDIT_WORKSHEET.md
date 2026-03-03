# DSCEngine – Audit radni list

Koristi ovaj dokument dok radiš audit. Za svaki odjeljak napiši svoje nalaze.

---

## 1. depositCollateral (linije 70–84)

```solidity
s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
emit CollateralDeposited(...);
bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
```

**Pitanja:**
- [ ] Redoslijed: mapping se ažurira PRIJE `transferFrom`. Što ako `transferFrom` ne uspije?
- [ ] Neki ERC20 tokeni (npr. USDT na Polygon) ne vraćaju `bool` iz `transfer`/`transferFrom`. Što se događa?
- [ ] Ima li `approve` prije ovog poziva? (Nije u ugovoru – očekuje se od usera. OK?)

**Tvoje bilješke:**
```
[tu napiši što si zaključio]
```

---

## 2. mintDsc (linije 124–131)

```solidity
s_DscMinted[msg.sender] += amountDscToMint;
_revertIfHealthFactorIsBroken(msg.sender);
bool minted = i_dsc.mint(msg.sender, amountDscToMint);
```

**Pitanja:**
- [ ] `s_DscMinted` se povećava PRIJE `mint`. Što ako `mint` reverta? (U Solidityju revert vrati sve – pa bi bilo OK. Provjeri.)
- [ ] Je li redoslijed ispravan? HF se provjerava prije mintanja – da, jer je s_DscMinted već povećan.

**Tvoje bilješke:**
```
[tu napiši]
```

---

## 3. _burnDsc (linije 185–193)

```solidity
s_DscMinted[onBehalfOf] -= amountDscToBurn;
bool success = i_dsc.transferFrom(dscfrom, address(this), amountDscToBurn);
```

**Pitanja:**
- [ ] Što ako `onBehalfOf` nema toliko u `s_DscMinted`? (underflow – Solidity 0.8+ reverta. Ali je li to uvijek provjereno prije poziva?)
- [ ] Tko može pozvati `_burnDsc`? Pogledaj: `burnDsc`, `redeemCollateralForDsc`, `liquidate`. U svakom slučaju – je li `dscfrom` uvijek ima dovoljno DSC-a?
- [ ] `burnDsc`: user burna svoj DSC – OK. `redeemCollateralForDsc`: user burna svoj – OK. `liquidate`: `dscfrom` je msg.sender (liquidator) – mora imati DSC. OK?

**Tvoje bilješke:**
```
[tu napiši]
```

---

## 4. redeemCollateralForDsc (linije 98–106)

```solidity
_burnDsc(amountDscToBurn, msg.sender, msg.sender);
_redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
_revertIfHealthFactorIsBroken(msg.sender);
```

**Pitanja:**
- [ ] Nema `nonReentrant`! `depositCollateral` i `mintDsc` ga imaju. Je li ovo reentrancy risk? (`_burnDsc` i `_redeemCollateral` zovu external tokene (ERC20). Mogu li ti tokeni dozvati reentrancy?)
- [ ] Što ako user proslijedi `amountDscToBurn = 0`? `moreThanZero` provjerava samo `amountCollateral`. Može li user redeemati kolateral bez burnanja DSC-a? (amountDscToBurn nije u modifieru – provjeri logiku!)

**Tvoje bilješke:**
```
[tu napiši]
```

---

## 5. liquidate (linije 138–161)

```solidity
_redeemCollateral(user, msg.sender, collateral, tokenAmountFromDebtCovered + bonusCollateral);
_burnDsc(debtToCover, user, msg.sender);
```

**Pitanja:**
- [ ] Redoslijed: prvo se uzima kolateral od usera, pa se burna DSC. Je li to sigurno? Što ako _burnDsc faila – je li kolateral već prebačen?
- [ ] Može li user imati manje kolaterala nego `tokenAmountFromDebtCovered + bonusCollateral`? Što se događa s `s_collateralDeposited[user][collateral] -= amount` – underflow?
- [ ] Chainlink `latestRoundData()` – dokumentacija kaže da treba provjeriti `answeredInRound`, `updatedAt`. Što ako je feed zastario ili vraća 0?

**Tvoje bilješke:**
```
[tu napiši]
```

---

## 6. Oracle / price feed (linije 207, 224)

```solidity
(, int256 price,,,) = priceFeed.latestRoundData();
return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
```

**Pitanja:**
- [ ] Što ako `price` je 0? Division by zero?
- [ ] Što ako `price` je negativan? `uint256(price)` će biti ogromna broj – može li Chainlink vratiti negativan?
- [ ] Chainlink preporučuje provjeru: `updatedAt`, `answeredInRound >= roundId`. Jesi li to provjerio?

**Tvoje bilješke:**
```
[tu napiši]
```

---

## 7. CEI pattern (Checks-Effects-Interactions)

Pravilo: prvo provjere, pa state promjene, pa external calls.

| Funkcija | Provjere | State | External | Ok? |
|----------|----------|-------|----------|-----|
| depositCollateral | modifiers | s_collateralDeposited += | transferFrom | ? |
| mintDsc | modifiers, HF | s_DscMinted += | mint | ? |
| _burnDsc | (nema u fn) | s_DscMinted -= | transferFrom, burn | ? |
| _redeemCollateral | (nema) | s_collateralDeposited -= | transfer | ? |

**Tvoje bilješke:**
```
[tu napiši – je li CEI poštovan?]
```

---

## 8. Checklist – brza provjera

- [ ] Svi external token callovi – vraćaju li bool? Što ako ne?
- [ ] Ima li funkcija koja zaboravlja provjeru HF?
- [ ] Može li netko likvidirati samog sebe? Ima li smisla?
- [ ] Dupli token u constructor? `tokenAddresses = [WETH, WETH]` – što se događa?
- [ ] Prazan array u constructor? `tokenAddresses.length == 0`

---

## 9. Što trebaš istražiti (homework)

1. **Chainlink**: Pročitaj [Data Feeds – Best Practices](https://docs.chain.link/data-feeds/price-feeds/check-the-latest-answer). Koje provjere preporučuju?
2. **ERC20**: Što je `safeTransfer` i zašto ga OpenZeppelin koristi? Razlika od običnog `transfer`?
3. **Reentrancy**: Zašto `redeemCollateralForDsc` nema `nonReentrant`? Je li `redeemCollateral` u opasnosti?

---

## 10. Sažetak nalaza

| # | Opis | Ozbiljnost (High/Med/Low/Info) | Status |
|---|------|-------------------------------|--------|
| 1 | | | |
| 2 | | | |
| 3 | | | |

---

*Nakon što popuniš, možeš pregledati s mentorom ili u grupi.*

---

## Dodatak: Alati

### Slither (statička analiza)
```bash
pip3 install slither-analyzer
cd foundry-defi-stablecoin-f23
slither . --config-file slither.config.json
```
Ako nemaš config, probaj: `slither src/DSCEngine.sol`

### Foundry – pokretanje testova
```bash
forge test -vvv
```

### Invariant test (napiši ih sam)
U test fajlu dodaj:
```solidity
function invariant_healthFactorMustBeAboveOne() public view {
    // Za svakog usera koji ima s_DscMinted > 0, HF mora biti >= 1
    // Kako doći do svih usera? Možda samo za known addresses u testu
}
```
