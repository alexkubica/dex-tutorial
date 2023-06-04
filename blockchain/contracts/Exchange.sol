// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Exchange is ERC20 {
    address public kubiTokenAddress;

    // Exchange is inheriting ERC20, because our exchange would keep track of Kubi LP tokens
    constructor(address _kubiTokenAddress) ERC20("Kubi LP Token", "KUBILP") {
        require(
            _kubiTokenAddress != address(0),
            "Token address passed is a null address"
        );
        kubiTokenAddress = _kubiTokenAddress;
    }

    /**
     * @dev Returns the amount of `Kubi Tokens` held by the contract
     */
    function getReserve() public view returns (uint) {
        return ERC20(kubiTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Adds liquidity to the exchange.
     */
    function addLiquidity(uint _amount) public payable returns (uint) {
        uint liquidity;
        uint ethBalance = address(this).balance;
        uint kubiTokenReserve = getReserve();
        ERC20 kubiToken = ERC20(kubiTokenAddress);
        /*
        If the reserve is empty, intake any user supplied value for
        `Ether` and `Kubi` tokens because there is no ratio currently
    */
        if (kubiTokenReserve == 0) {
            // Transfer the `kubiToken` from the user's account to the contract
            kubiToken.transferFrom(msg.sender, address(this), _amount);
            // Take the current ethBalance and mint `ethBalance` amount of LP tokens to the user.
            // `liquidity` provided is equal to `ethBalance` because this is the first time user
            // is adding `Eth` to the contract, so whatever `Eth` contract has is equal to the one supplied
            // by the user in the current `addLiquidity` call
            // `liquidity` tokens that need to be minted to the user on `addLiquidity` call should always be proportional
            // to the Eth specified by the user
            liquidity = ethBalance;
            _mint(msg.sender, liquidity);
            // _mint is ERC20.sol smart contract function to mint ERC20 tokens
        } else {
            /*
            If the reserve is not empty, intake any user supplied value for
            `Ether` and determine according to the ratio how many `Kubi` tokens
            need to be supplied to prevent any large price impacts because of the additional
            liquidity
        */
            // EthReserve should be the current ethBalance subtracted by the value of ether sent by the user
            // in the current `addLiquidity` call
            uint ethReserve = ethBalance - msg.value;
            // Ratio should always be maintained so that there are no major price impacts when adding liquidity
            // Ratio here is -> (kubiTokenAmount user can add/kubiTokenReserve in the contract) = (Eth Sent by the user/Eth Reserve in the contract);
            // So doing some maths, (kubiTokenAmount user can add) = (Eth Sent by the user * kubiTokenReserve /Eth Reserve);
            uint kubiTokenAmount = (msg.value * kubiTokenReserve) /
                (ethReserve);
            require(
                _amount >= kubiTokenAmount,
                "Amount of tokens sent is less than the minimum tokens required"
            );
            // transfer only (kubiTokenAmount user can add) amount of `Kubi tokens` from users account
            // to the contract
            kubiToken.transferFrom(msg.sender, address(this), kubiTokenAmount);
            // The amount of LP tokens that would be sent to the user should be proportional to the liquidity of
            // ether added by the user
            // Ratio here to be maintained is ->
            // (LP tokens to be sent to the user (liquidity)/ totalSupply of LP tokens in contract) = (Eth sent by the user)/(Eth reserve in the contract)
            // by some maths -> liquidity =  (totalSupply of LP tokens in contract * (Eth sent by the user))/(Eth reserve in the contract)
            liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);
        }
        return liquidity;
    }

    /**
     * @dev Returns the amount Eth/Kubi tokens that would be returned to the user
     * in the swap
     */
    function removeLiquidity(uint _amount) public returns (uint, uint) {
        require(_amount > 0, "_amount should be greater than zero");
        uint ethReserve = address(this).balance;
        uint _totalSupply = totalSupply();
        // The amount of Eth that would be sent back to the user is based
        // on a ratio
        // Ratio is -> (Eth sent back to the user) / (current Eth reserve)
        // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        // Then by some maths -> (Eth sent back to the user)
        // = (current Eth reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        uint ethAmount = (ethReserve * _amount) / _totalSupply;
        // The amount of Kubi token that would be sent back to the user is based
        // on a ratio
        // Ratio is -> (Kubi sent back to the user) / (current Kubi token reserve)
        // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        // Then by some maths -> (Kubi sent back to the user)
        // = (current Kubi token reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        uint kubiTokenAmount = (getReserve() * _amount) / _totalSupply;
        // Burn the sent LP tokens from the user's wallet because they are already sent to
        // remove liquidity
        _burn(msg.sender, _amount);
        // Transfer `ethAmount` of Eth from the contract to the user's wallet
        payable(msg.sender).transfer(ethAmount);
        // Transfer `kubivTokenAmount` of Kubi tokens from the contract to the user's wallet
        ERC20(kubiTokenAddress).transfer(msg.sender, kubiTokenAmount);
        return (ethAmount, kubiTokenAmount);
    }

    /**
     * @dev Returns the amount Eth/Kubi tokens that would be returned to the user
     * in the swap
     */
    function getAmountOfTokens(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");
        // We are charging a fee of `1%`
        // Input amount with fee = (input amount - (1*(input amount)/100)) = ((input amount)*99)/100
        uint256 inputAmountWithFee = inputAmount * 99;
        // Because we need to follow the concept of `XY = K` curve
        // We need to make sure (x + Δx) * (y - Δy) = x * y
        // So the final formula is Δy = (y * Δx) / (x + Δx)
        // Δy in our case is `tokens to be received`
        // Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        // So by putting the values in the formulae you can get the numerator and denominator
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
    }

    /**
     * @dev Swaps Eth for Kubi Tokens
     */
    function ethToKubiToken(uint _minTokens) public payable {
        uint256 tokenReserve = getReserve();
        // call the `getAmountOfTokens` to get the amount of Kubi tokens
        // that would be returned to the user after the swap
        // Notice that the `inputReserve` we are sending is equal to
        // `address(this).balance - msg.value` instead of just `address(this).balance`
        // because `address(this).balance` already contains the `msg.value` user has sent in the given call
        // so we need to subtract it to get the actual input reserve
        uint256 tokensBought = getAmountOfTokens(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );

        require(tokensBought >= _minTokens, "insufficient output amount");
        // Transfer the `Kubi` tokens to the user
        ERC20(kubiTokenAddress).transfer(msg.sender, tokensBought);
    }

    /**
     * @dev Swaps Kubi Tokens for Eth
     */
    function kubiTokenToEth(uint _tokensSold, uint _minEth) public {
        uint256 tokenReserve = getReserve();
        // call the `getAmountOfTokens` to get the amount of Eth
        // that would be returned to the user after the swap
        uint256 ethBought = getAmountOfTokens(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );
        require(ethBought >= _minEth, "insufficient output amount");
        // Transfer `Kubi` tokens from the user's address to the contract
        ERC20(kubiTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );
        // send the `ethBought` to the user from the contract
        payable(msg.sender).transfer(ethBought);
    }
}
