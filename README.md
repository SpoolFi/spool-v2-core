# Spool V2

## Standards

### Comments

[NatSpec format](https://docs.soliditylang.org/en/v0.8.17/natspec-format.html)

- External and private must include `@notice`.
- To explain technical implementation details you can optionally use `@dev`.
- Use dot `"."` at the end of the comment.
- Define `@param`
- Define `@return` with param name as the first word (e.g. `@return myVar Returning my variable value`).

TO comment struct parameters use `@custom:member` followed by the parameter value (e.g. `@custom:member myVar My variable`).


**Important: Add NatSpec docs to all functions before merging.**

### Function Names

[Solidity Style Guide](https://docs.soliditylang.org/en/v0.8.17/style-guide.html)

- use pascal case for function names
- private and internal function names start with the underscore "_"
- global private variables start with the underscore "_"
- constants are in capital letters TOKEN_NAME
- to avoid naming collision use underscore "_" as a postfix `singleTrailingUnderscore_`


test1 public
_test2 private

constructor(test1_, test2_, randomParam) {
    test1 = test1_;
    _test2 = test2_;
}

### Inheritance

First extend interfaces then implementations

```solidity
contract Abc is IAbc, INameable, Ownable, Asd { }
```

### Importing

First import external dependencies (e.g. OZ libs, implementations)

```solidity
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "./interfaces/ISmartVault.sol";
```
